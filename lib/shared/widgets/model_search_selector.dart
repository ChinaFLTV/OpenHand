import 'package:flutter/material.dart';

import '../../features/ai/model/ai_model_config.dart';
import 'animated_dialog.dart';

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
}) async {
  // Build flat list of entries grouped by provider.
  final entries = <ModelEntry>[];
  for (final config in models) {
    final allIds = config.allModelIds;
    if (allIds.isEmpty) {
      entries.add(ModelEntry(
        configId: config.id,
        modelId: config.modelId,
        providerLabel: config.providerLabel,
        protocolLabel: config.protocolType.storageValue,
      ));
    } else {
      for (final modelId in allIds) {
        entries.add(ModelEntry(
          configId: config.id,
          modelId: modelId,
          providerLabel: config.providerLabel,
          protocolLabel: config.protocolType.storageValue,
        ));
      }
    }
  }

  return showAnimatedDialog<(String, String)>(
    context: context,
    builder: (_) => _ModelSearchDialog(
      entries: entries,
      selectedConfigId: selectedConfigId,
      selectedModelId: selectedModelId,
    ),
  );
}

class _ModelSearchDialog extends StatefulWidget {
  const _ModelSearchDialog({
    required this.entries,
    this.selectedConfigId,
    this.selectedModelId,
  });

  final List<ModelEntry> entries;
  final String? selectedConfigId;
  final String? selectedModelId;

  @override
  State<_ModelSearchDialog> createState() => _ModelSearchDialogState();
}

class _ModelSearchDialogState extends State<_ModelSearchDialog> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
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
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isZh = Localizations.localeOf(context).languageCode == 'zh';

    // Group filtered entries by provider.
    final grouped = <String, List<ModelEntry>>{};
    for (final entry in _filtered) {
      final key = '${entry.providerLabel}  (${entry.protocolLabel})';
      (grouped[key] ??= []).add(entry);
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 520),
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
                    Navigator.of(context)
                        .pop((first.configId, first.modelId));
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
              child: _filtered.isEmpty
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
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 8),
                      itemCount: grouped.length,
                      itemBuilder: (context, groupIndex) {
                        final groupKey = grouped.keys.elementAt(groupIndex);
                        final groupEntries = grouped[groupKey]!;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Provider header.
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                16, 8, 16, 2,
                              ),
                              child: Text(
                                groupKey,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            // Model items.
                            for (final entry in groupEntries)
                              _ModelTile(
                                entry: entry,
                                isActive:
                                    entry.configId ==
                                        widget.selectedConfigId &&
                                    entry.modelId == widget.selectedModelId,
                                onTap: () {
                                  Navigator.of(context)
                                      .pop((entry.configId, entry.modelId));
                                },
                              ),
                          ],
                        );
                      },
                    ),
            ),
          ],
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
  });

  final ModelEntry entry;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
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
              child: Text(
                entry.modelId,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                  color: isActive ? colorScheme.primary : null,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

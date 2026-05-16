part of 'hardness_session_dashboard.dart';

class _HeModelDropdown extends StatelessWidget {
  const _HeModelDropdown({
    required this.roleConfig,
    required this.isZh,
    required this.onChanged,
  });

  final HardnessRoleConfig roleConfig;
  final bool isZh;
  final ValueChanged<HardnessRoleConfig> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cli = kHardnessCliCatalog
        .where((c) => c.name == roleConfig.cliName)
        .firstOrNull;
    final models = cli?.knownModels ?? const [];
    final configuredModelId = roleConfig.modelId.trim();

    if (models.isEmpty) {
      // Free-form text field for model ID.
      return TextFormField(
        key: ValueKey<String>('he-model-text-${roleConfig.cliName}'),
        initialValue: roleConfig.modelId,
        decoration: InputDecoration(
          labelText: isZh ? '模型' : 'Model',
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        style: theme.textTheme.bodySmall,
        onChanged: (value) =>
            onChanged(roleConfig.copyWith(modelId: value.trim())),
      );
    }

    final items = <DropdownMenuItem<String>>[];
    if (configuredModelId.isNotEmpty && !models.contains(configuredModelId)) {
      items.add(
        DropdownMenuItem<String>(
          value: configuredModelId,
          child: Text(
            describeHardnessCliModel(cli, configuredModelId, isZh: isZh),
            style: theme.textTheme.bodySmall,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }

    return DropdownButtonFormField<String>(
      initialValue: items.any((item) => item.value == configuredModelId)
          ? configuredModelId
          : (models.contains(configuredModelId) ? configuredModelId : null),
      decoration: InputDecoration(
        labelText: isZh ? '模型' : 'Model',
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      items: [
        ...items,
        ...models.map((m) {
          return DropdownMenuItem(
            value: m,
            child: Text(
              describeHardnessCliModel(cli, m, isZh: isZh),
              style: theme.textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          );
        }),
      ],
      onChanged: (value) {
        if (value == null) return;
        onChanged(roleConfig.copyWith(modelId: value));
      },
    );
  }
}

// =============================================================================
// _HeUrlModelField — tap-to-search URL/API model selector for pending phases
// =============================================================================

class _HeUrlModelField extends StatelessWidget {
  const _HeUrlModelField({
    required this.settingsModels,
    required this.roleConfig,
    required this.isZh,
    required this.hasConfiguredAiModelConfig,
    required this.hasMatchingAiModelConfig,
    required this.onChanged,
  });

  final List<AiModelConfig> settingsModels;
  final HardnessRoleConfig roleConfig;
  final bool isZh;
  final bool hasConfiguredAiModelConfig;
  final bool hasMatchingAiModelConfig;
  final ValueChanged<HardnessRoleConfig> onChanged;

  String? get _displayLabel {
    final id = roleConfig.aiModelConfigId?.trim();
    if (id == null || id.isEmpty) return null;
    final config = settingsModels.where((m) => m.id == id).firstOrNull;
    if (config == null) return null;
    final modelId = roleConfig.urlModeModelId?.trim();
    if (modelId != null && modelId.isNotEmpty) return modelId;
    if (config.modelId.trim().isNotEmpty) return config.modelId;
    return config.providerLabel;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final settingsController = Provider.of<SettingsController?>(
      context,
      listen: false,
    );
    final label = _displayLabel;
    return GestureDetector(
      onTap: settingsModels.isEmpty
          ? null
          : () async {
              final result = await showModelSearchSelector(
                context: context,
                models: settingsModels,
                recentSelections:
                    settingsController?.recentModelSelections ?? const [],
                selectedConfigId: roleConfig.aiModelConfigId,
                selectedModelId: roleConfig.urlModeModelId,
              );
              if (result != null) {
                settingsController?.addRecentModelSelection(
                  result.$1,
                  result.$2,
                );
                onChanged(
                  roleConfig.copyWith(
                    aiModelConfigId: result.$1,
                    urlModeModelId: result.$2,
                  ),
                );
              }
            },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: isZh ? 'API 模型' : 'API Model',
          helperText: settingsModels.isEmpty
              ? (isZh
                    ? '请先在设置中配置 API 模型提供商。'
                    : 'Configure API model providers in Settings first.')
              : (hasConfiguredAiModelConfig && !hasMatchingAiModelConfig)
              ? (isZh
                    ? '当前配置已删除，请重新选择。'
                    : 'Current config was deleted. Choose another.')
              : null,
          helperMaxLines: 2,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          suffixIcon: Icon(
            Icons.arrow_drop_down_rounded,
            size: 20,
            color: colorScheme.onSurfaceVariant,
          ),
          suffixIconConstraints: const BoxConstraints(
            minWidth: 24,
            minHeight: 24,
          ),
        ),
        child: Text(
          label ?? (isZh ? '选择模型…' : 'Select model…'),
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            color: label != null
                ? colorScheme.onSurface
                : colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// _HeChangedFilesList — shows files changed during a phase execution
// =============================================================================

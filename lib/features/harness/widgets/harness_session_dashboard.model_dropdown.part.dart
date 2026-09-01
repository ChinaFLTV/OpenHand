part of 'harness_session_dashboard.dart';

class _HeModelDropdown extends StatelessWidget {
  const _HeModelDropdown({required this.roleConfig, required this.onChanged});

  final HarnessRoleConfig roleConfig;
  final ValueChanged<HarnessRoleConfig> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cli = kHarnessCliCatalog
        .where((c) => c.name == roleConfig.cliName)
        .firstOrNull;
    final models = cli?.knownModels ?? const [];
    final configuredModelId = roleConfig.modelId.trim();

    if (models.isEmpty) {
      return TextFormField(
        key: ValueKey<String>('he-model-text-${roleConfig.cliName}'),
        initialValue: roleConfig.modelId,
        decoration: InputDecoration(
          labelText: openHandModelLabel(context),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          border: const OutlineInputBorder(borderRadius: _br12),
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
            describeHarnessCliModel(
              configuredModelId,
              locale: Localizations.localeOf(context),
            ),
            style: theme.textTheme.bodySmall,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }

    return AnimatedDropdownButtonFormField<String>(
      initialValue: items.any((item) => item.value == configuredModelId)
          ? configuredModelId
          : (models.contains(configuredModelId) ? configuredModelId : null),
      decoration: InputDecoration(
        labelText: openHandModelLabel(context),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: const OutlineInputBorder(borderRadius: _br12),
      ),
      items: [
        ...items,
        ...models.map((m) {
          return DropdownMenuItem(
            value: m,
            child: Text(
              describeHarnessCliModel(
                m,
                locale: Localizations.localeOf(context),
              ),
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

// _HeUrlModelField — tap-to-search URL/API model selector for pending phases
class _HeUrlModelField extends StatelessWidget {
  const _HeUrlModelField({
    required this.settingsModels,
    required this.roleConfig,
    required this.hasConfiguredAiModelConfig,
    required this.hasMatchingAiModelConfig,
    required this.onChanged,
  });

  final List<AiModelConfig> settingsModels;
  final HarnessRoleConfig roleConfig;
  final bool hasConfiguredAiModelConfig;
  final bool hasMatchingAiModelConfig;
  final ValueChanged<HarnessRoleConfig> onChanged;

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
    return OpenHandTapRegion(
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
          labelText: openHandApiModelLabel(context),
          helperText: settingsModels.isEmpty
              ? openHandLocalizedText(
                  context,
                  zh: '请先在设置中配置 API 模型提供商。',
                  zhHant: '請先在設定中設定 API 模型提供者。',
                  en: 'Configure API model providers in Settings first.',
                  fr: 'Configurez d’abord les fournisseurs de modèles API dans les paramètres.',
                  de: 'Konfiguriere zuerst API-Modellanbieter in den Einstellungen.',
                  ja: '先に設定で API モデルプロバイダーを設定してください。',
                )
              : (hasConfiguredAiModelConfig && !hasMatchingAiModelConfig)
              ? openHandLocalizedText(
                  context,
                  zh: '当前配置已删除，请重新选择。',
                  zhHant: '目前設定已刪除，請重新選擇。',
                  en: 'Current config was deleted. Choose another.',
                  fr: 'La configuration actuelle a été supprimée. Choisissez-en une autre.',
                  de: 'Die aktuelle Konfiguration wurde gelöscht. Wähle eine andere.',
                  ja: '現在の設定は削除済みです。別の設定を選択してください。',
                )
              : null,
          helperMaxLines: 2,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          border: const OutlineInputBorder(borderRadius: _br12),
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
          label ??
              openHandLocalizedText(
                context,
                zh: '选择模型…',
                zhHant: '選擇模型…',
                en: 'Select model…',
                fr: 'Sélectionner un modèle…',
                de: 'Modell auswählen…',
                ja: 'モデルを選択…',
              ),
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

// _HeChangedFilesList — shows files changed during a phase execution

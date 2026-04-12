part of 'settings_view.dart';

class _PaneHeader extends StatelessWidget {
  const _PaneHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.displaySmall),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _SettingsGroupCard extends StatelessWidget {
  const _SettingsGroupCard({
    required this.title,
    required this.description,
    required this.children,
  });

  final String title;
  final String description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: double.infinity,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                description,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              ..._intersperse(children, const SizedBox(height: 18)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsSubsectionCard extends StatelessWidget {
  const _SettingsSubsectionCard({
    required this.title,
    required this.description,
    required this.child,
  });

  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              description,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _ThemePresetSwatch extends StatelessWidget {
  const _ThemePresetSwatch({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final outlineColor = Theme.of(context).colorScheme.outlineVariant;

    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: outlineColor),
      ),
    );
  }
}

class _ResponsiveSettingRow extends StatelessWidget {
  const _ResponsiveSettingRow({
    required this.title,
    required this.subtitle,
    required this.control,
    this.controlMaxWidth = 320,
  });

  final String title;
  final String subtitle;
  final Widget control;
  final double controlMaxWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 760;
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              control,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 20),
            Flexible(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: controlMaxWidth),
                child: control,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ReadonlySettingRow extends StatelessWidget {
  const _ReadonlySettingRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 680;
          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                SelectableText(value, style: theme.textTheme.bodyLarge),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 140,
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Expanded(
                child: SelectableText(value, style: theme.textTheme.bodyLarge),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SettingsStateBox extends StatelessWidget {
  const _SettingsStateBox({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(18),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: colorScheme.onPrimaryContainer),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleLarge),
                  const SizedBox(height: 6),
                  Text(
                    body,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
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

class _SettingsPersistenceIssueCard extends StatelessWidget {
  const _SettingsPersistenceIssueCard({
    required this.issue,
    required this.onDismiss,
  });

  final SettingsPersistenceIssue issue;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final (title, body) = switch (issue.kind) {
      SettingsPersistenceIssueKind.recoveredInvalidFile => (
        l10n.settingsPersistenceRecoveredTitle,
        '${l10n.settingsPersistenceRecoveredBody}\n${OpenHandPaths.shortenHomePath(issue.filePath)}',
      ),
      SettingsPersistenceIssueKind.sanitizedInvalidContent => (
        l10n.settingsPersistenceSanitizedTitle,
        '${l10n.settingsPersistenceSanitizedBody}\n${OpenHandPaths.shortenHomePath(issue.filePath)}',
      ),
      SettingsPersistenceIssueKind.saveFailed => (
        l10n.settingsPersistenceSaveFailedTitle,
        '${l10n.settingsPersistenceSaveFailedBody}\n${OpenHandPaths.shortenHomePath(issue.filePath)}',
      ),
    };

    return Card(
      color: colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: colorScheme.onErrorContainer,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    body,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onErrorContainer,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: onDismiss,
              tooltip: l10n.settingsPersistenceDismiss,
              icon: Icon(
                Icons.close_rounded,
                color: colorScheme.onErrorContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AiProviderModelChip extends StatelessWidget {
  const _AiProviderModelChip({
    required this.modelId,
    required this.isActive,
    required this.onPressed,
    this.onDeleted,
    this.tooltip,
    this.compact = false,
    this.enabled = true,
  });

  final String modelId;
  final bool isActive;
  final VoidCallback onPressed;
  final VoidCallback? onDeleted;
  final String? tooltip;
  final bool compact;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final inactiveBaseColor = colorScheme.surfaceContainerHighest.withValues(
      alpha: isDark ? 0.54 : 0.94,
    );
    final inactiveHoverColor = Color.alphaBlend(
      colorScheme.onSurface.withValues(alpha: isDark ? 0.04 : 0.02),
      Color.lerp(inactiveBaseColor, colorScheme.surfaceContainerHigh, 0.56) ??
          inactiveBaseColor,
    );
    final inactivePressedColor = Color.alphaBlend(
      colorScheme.primary.withValues(alpha: isDark ? 0.07 : 0.03),
      Color.lerp(inactiveBaseColor, colorScheme.surfaceContainerHigh, 0.82) ??
          inactiveBaseColor,
    );
    final activeBaseColor = Color.alphaBlend(
      colorScheme.primary.withValues(alpha: isDark ? 0.10 : 0.03),
      Color.lerp(
            colorScheme.surfaceContainerLowest,
            colorScheme.primaryContainer,
            isDark ? 0.74 : 0.66,
          ) ??
          colorScheme.primaryContainer,
    );
    final activeHoverColor = Color.alphaBlend(
      colorScheme.primary.withValues(alpha: isDark ? 0.14 : 0.05),
      Color.lerp(activeBaseColor, colorScheme.primaryContainer, 0.36) ??
          activeBaseColor,
    );
    final activePressedColor = Color.alphaBlend(
      colorScheme.primary.withValues(alpha: isDark ? 0.18 : 0.08),
      Color.lerp(
            activeBaseColor,
            colorScheme.primary,
            isDark ? 0.14 : 0.10,
          ) ??
          activeBaseColor,
    );
    final labelColor = isActive
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurfaceVariant;
    final accentColor = isActive
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;
    final borderColor = isActive
        ? colorScheme.primary.withValues(alpha: isDark ? 0.62 : 0.52)
        : colorScheme.outlineVariant.withValues(alpha: isDark ? 0.76 : 0.94);
    final fillColor = WidgetStateProperty.resolveWith<Color?>((states) {
      final selected = states.contains(WidgetState.selected);
      final pressed = states.contains(WidgetState.pressed);
      final hovered = states.contains(WidgetState.hovered);
      final disabled = states.contains(WidgetState.disabled);
      if (selected) {
        if (disabled) {
          return activeBaseColor.withValues(alpha: isDark ? 0.56 : 0.72);
        }
        if (pressed) {
          return activePressedColor;
        }
        if (hovered) {
          return activeHoverColor;
        }
        return activeBaseColor;
      }
      if (disabled) {
        return inactiveBaseColor.withValues(alpha: isDark ? 0.42 : 0.72);
      }
      if (pressed) {
        return inactivePressedColor;
      }
      if (hovered) {
        return inactiveHoverColor;
      }
      return inactiveBaseColor;
    });
    final effectiveOnPressed = enabled ? onPressed : null;
    final effectiveOnDeleted = enabled ? onDeleted : null;
    final chip = InputChip(
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
      mouseCursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      elevation: 0,
      pressElevation: isActive ? 0.8 : 0.45,
      shadowColor: colorScheme.primary.withValues(alpha: isDark ? 0.22 : 0.12),
      selectedShadowColor: colorScheme.primary.withValues(
        alpha: isDark ? 0.30 : 0.18,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 6,
      ),
      labelPadding: EdgeInsets.symmetric(horizontal: compact ? 1 : 2),
      label: Text(
        modelId,
        style:
            (compact ? theme.textTheme.labelSmall : theme.textTheme.labelMedium)
                ?.copyWith(
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: labelColor,
                ),
      ),
      avatar: Icon(
        isActive ? Icons.star_rounded : Icons.smart_toy_outlined,
        size: compact ? 14 : 16,
        color: accentColor,
      ),
      selected: isActive,
      showCheckmark: false,
      color: fillColor,
      side: BorderSide(color: borderColor, width: isActive ? 1.15 : 1),
      onSelected: effectiveOnPressed == null ? null : (_) => effectiveOnPressed(),
      onDeleted: effectiveOnDeleted,
      deleteIcon: effectiveOnDeleted == null
          ? null
          : Icon(
              Icons.close_rounded,
              size: compact ? 14 : 16,
              color: accentColor,
            ),
    );

    Widget result = chip;
    final trimmedTooltip = tooltip?.trim();
    if (enabled && trimmedTooltip != null && trimmedTooltip.isNotEmpty) {
      result = Tooltip(message: trimmedTooltip, child: result);
    }
    return result;
  }
}

class _AiModelTile extends StatelessWidget {
  const _AiModelTile({
    required this.model,
    required this.isSelected,
    required this.isTesting,
    required this.isFirst,
    required this.isLast,
    required this.onSelect,
    required this.onTest,
    required this.onEdit,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onDelete,
    required this.onActiveModelChanged,
  });

  final AiModelConfig model;
  final bool isSelected;
  final bool isTesting;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onSelect;
  final VoidCallback onTest;
  final VoidCallback onEdit;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onDelete;
  final void Function(String modelId) onActiveModelChanged;

  String _localizedText(
    BuildContext context, {
    required String zh,
    required String en,
  }) {
    final languageCode = Localizations.localeOf(context).languageCode;
    return languageCode.startsWith('zh') ? zh : en;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final allModels = model.allModelIds;
    final modelCountLabel = allModels.isNotEmpty
        ? l10n.aiModelCount(allModels.length)
        : _localizedText(context, zh: '无模型', en: 'No models');

    return InkWell(
      onTap: onSelect,
      borderRadius: BorderRadius.circular(24),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primaryContainer.withValues(alpha: 0.52)
              : colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected
                ? colorScheme.primary
                : colorScheme.outlineVariant,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          model.providerLabel,
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${model.protocolType.label(l10n)} · ${model.authScheme.label(l10n)} · $modelCountLabel',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (model.modelId.trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            _localizedText(
                              context,
                              zh: '当前模型：${model.modelId}',
                              en: 'Active: ${model.modelId}',
                            ),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Wrap(
                    spacing: 4,
                    children: [
                      IconButton(
                        onPressed: isFirst ? null : onMoveUp,
                        tooltip: l10n.aiModelMoveUp,
                        icon: const Icon(Icons.arrow_upward_rounded),
                      ),
                      IconButton(
                        onPressed: isLast ? null : onMoveDown,
                        tooltip: l10n.aiModelMoveDown,
                        icon: const Icon(Icons.arrow_downward_rounded),
                      ),
                      IconButton(
                        onPressed: onEdit,
                        tooltip: l10n.commonEdit,
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        onPressed: onDelete,
                        tooltip: l10n.commonDelete,
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                      IconButton(
                        onPressed: isTesting ? null : onTest,
                        tooltip: isTesting
                            ? l10n.aiModelTesting
                            : l10n.aiModelTest,
                        icon: isTesting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.network_check_rounded),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  Chip(
                    avatar: const Icon(Icons.link_rounded, size: 18),
                    label: Text(model.normalizedBaseUrl),
                  ),
                  Chip(
                    avatar: const Icon(Icons.vpn_key_outlined, size: 18),
                    label: Text(
                      model.maskedToken.isEmpty
                          ? l10n.aiModelNoToken
                          : model.maskedToken,
                    ),
                  ),
                  if (isSelected)
                    Chip(
                      avatar: const Icon(
                        Icons.check_circle_outline_rounded,
                        size: 18,
                      ),
                      label: Text(l10n.aiModelSelected),
                    ),
                ],
              ),
              // Show available models as small chips; active model is highlighted.
              // When a provider has many models, truncate to avoid excessive
              // card height and reduce widget-build cost during scrolling.
              if (allModels.isNotEmpty) ...[
                const SizedBox(height: 10),
                RepaintBoundary(
                  child: Builder(builder: (ctx) {
                    const maxVisible = 20;
                    final activeId = model.modelId;
                    // Ensure the active model always appears first.
                    final ordered = <String>[
                      if (allModels.contains(activeId)) activeId,
                      ...allModels.where((id) => id != activeId),
                    ];
                    final visible = ordered.length <= maxVisible
                        ? ordered
                        : ordered.sublist(0, maxVisible);
                    final hiddenCount = ordered.length - visible.length;
                    return Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        for (final id in visible)
                          _AiProviderModelChip(
                            modelId: id,
                            isActive: id == activeId,
                            compact: true,
                            tooltip: id == activeId
                                ? _localizedText(
                                    ctx,
                                    zh: '当前活跃模型',
                                    en: 'Currently active model',
                                  )
                                : _localizedText(
                                    ctx,
                                    zh: '点击切换为活跃模型',
                                    en: 'Click to set as active model',
                                  ),
                            onPressed: id == activeId
                                ? () {}
                                : () => onActiveModelChanged(id),
                          ),
                        if (hiddenCount > 0)
                          Tooltip(
                            message: _localizedText(
                              ctx,
                              zh: '还有 $hiddenCount 个模型，点击编辑查看全部',
                              en: '$hiddenCount more models – edit to see all',
                            ),
                            child: Chip(
                              avatar: const Icon(Icons.more_horiz_rounded, size: 16),
                              label: Text('+$hiddenCount'),
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                      ],
                    );
                  }),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

part of 'settings_view.dart';

const int _aiModelChipPreviewLimit = 8;

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

class _SettingsElasticExpansion extends StatelessWidget {
  const _SettingsElasticExpansion({
    required this.expanded,
    required this.child,
  });

  final bool expanded;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 280);
    final reverseDuration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 190);

    return AnimatedSize(
      duration: duration,
      reverseDuration: reverseDuration,
      curve: Curves.easeOutCubic,
      alignment: Alignment.topLeft,
      child: ClipRect(
        child: AnimatedSwitcher(
          duration: duration,
          reverseDuration: reverseDuration,
          switchInCurve: Curves.easeOutBack,
          switchOutCurve: Curves.easeInCubic,
          layoutBuilder: (currentChild, previousChildren) => Stack(
            alignment: Alignment.topLeft,
            children: <Widget>[
              ...previousChildren,
              if (currentChild != null) currentChild,
            ],
          ),
          transitionBuilder: (transitionChild, animation) {
            final eased = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutBack,
              reverseCurve: Curves.easeInCubic,
            );
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, -0.018),
                  end: Offset.zero,
                ).animate(eased),
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.985, end: 1).animate(eased),
                  alignment: Alignment.topCenter,
                  child: transitionChild,
                ),
              ),
            );
          },
          child: expanded
              ? Padding(
                  key: const ValueKey<String>('expanded'),
                  padding: const EdgeInsets.only(top: 8),
                  child: child,
                )
              : const SizedBox.shrink(key: ValueKey<String>('collapsed')),
        ),
      ),
    );
  }
}

class _SettingsExpandIcon extends StatelessWidget {
  const _SettingsExpandIcon({required this.expanded});

  final bool expanded;

  @override
  Widget build(BuildContext context) {
    return AnimatedRotation(
      turns: expanded ? 0.5 : 0,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 220),
      curve: Curves.easeOutBack,
      child: const Icon(Icons.expand_more_rounded),
    );
  }
}

Widget _settingsTransparentReorderProxy(
  BuildContext context,
  Widget child,
  int index,
  Animation<double> animation,
) {
  final colorScheme = Theme.of(context).colorScheme;
  final reduceMotion = MediaQuery.disableAnimationsOf(context);
  final eased = CurvedAnimation(parent: animation, curve: Curves.easeOutBack);

  return AnimatedBuilder(
    animation: animation,
    child: Material(
      type: MaterialType.transparency,
      color: Colors.transparent,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      child: child,
    ),
    builder: (context, proxyChild) {
      final t = reduceMotion ? 1.0 : eased.value;
      return Transform.scale(
        scale: 1 + 0.018 * t,
        child: DecoratedBox(
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withValues(alpha: 0.12 * t),
                blurRadius: 18 * t,
                offset: Offset(0, 8 * t),
              ),
            ],
          ),
          child: proxyChild,
        ),
      );
    },
  );
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
    this.onEdit,
    this.onDeleted,
    this.tooltip,
    this.compact = false,
    this.enabled = true,
    this.hasProfile = false,
  });

  final String modelId;
  final bool isActive;
  final VoidCallback onPressed;
  final VoidCallback? onEdit;
  final VoidCallback? onDeleted;
  final String? tooltip;
  final bool compact;
  final bool enabled;
  final bool hasProfile;

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
      Color.lerp(activeBaseColor, colorScheme.primary, isDark ? 0.14 : 0.10) ??
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
    final effectiveOnPressed = enabled ? onPressed : null;
    final effectiveOnEdit = enabled ? onEdit : null;
    final effectiveOnDeleted = enabled ? onDeleted : null;
    final iconSize = compact ? 14.0 : 16.0;

    // Resolve background color: InputChip's _RenderChip swallows taps from
    // GestureDetectors nested inside its label, preventing action icons from
    // firing.  A plain Material + InkWell avoids that gesture-arena conflict
    // while preserving the same visual appearance.
    final baseColor = enabled
        ? (isActive ? activeBaseColor : inactiveBaseColor)
        : (isActive
              ? activeBaseColor.withValues(alpha: isDark ? 0.56 : 0.72)
              : inactiveBaseColor.withValues(alpha: isDark ? 0.42 : 0.72));

    Widget chip = Material(
      clipBehavior: Clip.antiAlias,
      shape: StadiumBorder(
        side: BorderSide(color: borderColor, width: isActive ? 1.15 : 1),
      ),
      color: baseColor,
      shadowColor: isActive
          ? colorScheme.primary.withValues(alpha: isDark ? 0.30 : 0.18)
          : colorScheme.primary.withValues(alpha: isDark ? 0.22 : 0.12),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: effectiveOnPressed,
        hoverColor: isActive ? activeHoverColor : inactiveHoverColor,
        highlightColor: isActive ? activePressedColor : inactivePressedColor,
        splashColor: (isActive ? activePressedColor : inactivePressedColor)
            .withValues(alpha: 0.32),
        mouseCursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        child: Padding(
          padding: EdgeInsets.only(
            left: compact ? 8 : 10,
            right: (effectiveOnEdit != null || effectiveOnDeleted != null)
                ? (compact ? 4 : 5)
                : (compact ? 8 : 10),
            top: compact ? 4 : 6,
            bottom: compact ? 4 : 6,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                isActive ? Icons.star_rounded : Icons.smart_toy_outlined,
                size: compact ? 14 : 16,
                color: accentColor,
              ),
              SizedBox(width: compact ? 5 : 7),
              Flexible(
                child: Text(
                  modelId,
                  overflow: TextOverflow.ellipsis,
                  style:
                      (compact
                              ? theme.textTheme.labelSmall
                              : theme.textTheme.labelMedium)
                          ?.copyWith(
                            fontWeight: isActive
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: labelColor,
                          ),
                ),
              ),
              if (effectiveOnEdit != null) ...<Widget>[
                const SizedBox(width: 4),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: effectiveOnEdit,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Icon(
                      hasProfile ? Icons.tune_rounded : Icons.tune_outlined,
                      size: iconSize,
                      color: hasProfile ? colorScheme.primary : accentColor,
                    ),
                  ),
                ),
              ],
              if (effectiveOnDeleted != null) ...<Widget>[
                const SizedBox(width: 2),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: effectiveOnDeleted,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Icon(
                      Icons.close_rounded,
                      size: iconSize,
                      color: accentColor,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    Widget result = ConstrainedBox(
      constraints: BoxConstraints(minHeight: compact ? 26 : 32),
      child: chip,
    );
    if (enabled && effectiveOnPressed != null) {
      result = MicroPressFeedback(child: result);
    }
    final trimmedTooltip = tooltip?.trim();
    if (enabled && trimmedTooltip != null && trimmedTooltip.isNotEmpty) {
      result = Tooltip(message: trimmedTooltip, child: result);
    }
    return result;
  }
}

class _AiProviderOverflowChip extends StatelessWidget {
  const _AiProviderOverflowChip({
    required this.hiddenCount,
    required this.onPressed,
    required this.tooltip,
  });

  final int hiddenCount;
  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final child = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 26),
      child: Material(
        clipBehavior: Clip.antiAlias,
        shape: StadiumBorder(
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.94),
          ),
        ),
        color: colorScheme.surfaceContainerHighest.withValues(
          alpha: theme.brightness == Brightness.dark ? 0.54 : 0.94,
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onPressed,
          hoverColor: colorScheme.primary.withValues(alpha: 0.07),
          highlightColor: colorScheme.primary.withValues(alpha: 0.10),
          splashColor: colorScheme.primary.withValues(alpha: 0.12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.more_horiz_rounded,
                  size: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 5),
                Text(
                  '+$hiddenCount',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return Tooltip(
      message: tooltip,
      child: MicroPressFeedback(child: child),
    );
  }
}

class _AiModelTile extends StatefulWidget {
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

  @override
  State<_AiModelTile> createState() => _AiModelTileState();
}

class _AiModelTileState extends State<_AiModelTile> {
  bool _modelChipsExpanded = false;

  /// 2026-05-19 — APP 运行期间稳定的胶囊排序。冷启动后第一次构建本卡片
  /// 时按"活跃模型优先"排好；之后用户切换活跃模型，胶囊位置不再动 —
  /// 仅高亮跟随。只有当模型列表本身（增/删/重命名）变了，或卡片重挂载
  /// 时才会按新顺序重新快照。
  List<String>? _stableChipOrder;

  List<String> _resolveStableChipOrder(List<String> allModels, String activeId) {
    final cached = _stableChipOrder;
    if (cached != null) {
      // 同集合（顺序无关）即可复用，避免新增/删除模型后阵列错乱。
      final cachedSet = cached.toSet();
      final allSet = allModels.toSet();
      if (cachedSet.length == allSet.length && cachedSet.containsAll(allSet)) {
        return cached;
      }
    }
    final fresh = <String>[
      if (allModels.contains(activeId)) activeId,
      ...allModels.where((id) => id != activeId),
    ];
    _stableChipOrder = fresh;
    return fresh;
  }

  @override
  void didUpdateWidget(covariant _AiModelTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.model.id != widget.model.id) {
      _modelChipsExpanded = false;
    } else if (_modelChipsExpanded &&
        widget.model.allModelIds.length <= _aiModelChipPreviewLimit) {
      _modelChipsExpanded = false;
    }
  }

  void _toggleModelChipsExpanded() {
    HapticFeedback.selectionClick();
    setState(() {
      _modelChipsExpanded = !_modelChipsExpanded;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final allModels = widget.model.allModelIds;
    final modelCountLabel = allModels.isNotEmpty
        ? l10n.aiModelCount(allModels.length)
        : _localizedText(context, zh: '无模型', en: 'No models');
    final canExpandModels = allModels.length > _aiModelChipPreviewLimit;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return MicroPressFeedback(
      child: InkWell(
        onTap: widget.onSelect,
        borderRadius: BorderRadius.circular(24),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: widget.isSelected
                ? colorScheme.primaryContainer.withValues(alpha: 0.52)
                : colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: widget.isSelected
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
                            widget.model.providerLabel,
                            style: theme.textTheme.titleLarge,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${widget.model.protocolType.label(l10n)} · ${widget.model.authScheme.label(l10n)} · $modelCountLabel',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (widget.model.modelId.trim().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              _localizedText(
                                context,
                                zh: '当前模型：${widget.model.modelId}',
                                en: 'Active: ${widget.model.modelId}',
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
                        if (canExpandModels)
                          IconButton(
                            onPressed: _toggleModelChipsExpanded,
                            tooltip: _modelChipsExpanded
                                ? _localizedText(
                                    context,
                                    zh: '折叠模型列表',
                                    en: 'Collapse model list',
                                  )
                                : _localizedText(
                                    context,
                                    zh: '展开全部模型',
                                    en: 'Show all models',
                                  ),
                            icon: AnimatedSwitcher(
                              duration: reduceMotion
                                  ? Duration.zero
                                  : const Duration(milliseconds: 220),
                              switchInCurve: Curves.easeOutBack,
                              switchOutCurve: Curves.easeInCubic,
                              transitionBuilder: (child, animation) =>
                                  FadeTransition(
                                    opacity: animation,
                                    child: ScaleTransition(
                                      scale: animation,
                                      child: child,
                                    ),
                                  ),
                              child: Icon(
                                _modelChipsExpanded
                                    ? Icons.unfold_less_rounded
                                    : Icons.unfold_more_rounded,
                                key: ValueKey<bool>(_modelChipsExpanded),
                              ),
                            ),
                          ),
                        IconButton(
                          onPressed: widget.isFirst ? null : widget.onMoveUp,
                          tooltip: l10n.aiModelMoveUp,
                          icon: const Icon(Icons.arrow_upward_rounded),
                        ),
                        IconButton(
                          onPressed: widget.isLast ? null : widget.onMoveDown,
                          tooltip: l10n.aiModelMoveDown,
                          icon: const Icon(Icons.arrow_downward_rounded),
                        ),
                        IconButton(
                          onPressed: widget.onEdit,
                          tooltip: l10n.commonEdit,
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          onPressed: widget.onDelete,
                          tooltip: l10n.commonDelete,
                          icon: const Icon(Icons.delete_outline_rounded),
                        ),
                        IconButton(
                          onPressed: widget.isTesting ? null : widget.onTest,
                          tooltip: widget.isTesting
                              ? l10n.aiModelTesting
                              : l10n.aiModelTest,
                          icon: widget.isTesting
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
                      label: Text(widget.model.normalizedBaseUrl),
                    ),
                    Chip(
                      avatar: const Icon(Icons.vpn_key_outlined, size: 18),
                      label: Text(
                        widget.model.maskedToken.isEmpty
                            ? l10n.aiModelNoToken
                            : widget.model.maskedToken,
                      ),
                    ),
                    if (widget.isSelected)
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
                    child: Builder(
                      builder: (ctx) {
                        final activeId = widget.model.modelId;
                        // 仅在冷启动 / 模型列表变化时按"活跃优先"排序，
                        // 否则保持现有顺序，避免点胶囊后该胶囊跳到首位。
                        final ordered = _resolveStableChipOrder(
                          allModels,
                          activeId,
                        );
                        final visible =
                            _modelChipsExpanded ||
                                ordered.length <= _aiModelChipPreviewLimit
                            ? ordered
                            : ordered.sublist(0, _aiModelChipPreviewLimit);
                        final hiddenCount = ordered.length - visible.length;
                        return AnimatedSize(
                          alignment: Alignment.topLeft,
                          duration: reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 420),
                          reverseDuration: reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 260),
                          curve: Curves.easeOutBack,
                          child: AnimatedSwitcher(
                            duration: reduceMotion
                                ? Duration.zero
                                : const Duration(milliseconds: 260),
                            switchInCurve: Curves.easeOutBack,
                            switchOutCurve: Curves.easeInCubic,
                            layoutBuilder: (currentChild, previousChildren) {
                              return Stack(
                                children: <Widget>[
                                  ...previousChildren,
                                  if (currentChild != null) currentChild,
                                ],
                              );
                            },
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                                  opacity: animation,
                                  child: ScaleTransition(
                                    alignment: Alignment.topLeft,
                                    scale: Tween<double>(
                                      begin: 0.98,
                                      end: 1,
                                    ).animate(animation),
                                    child: child,
                                  ),
                                ),
                            child: Wrap(
                              key: ValueKey<bool>(_modelChipsExpanded),
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
                                        : () => widget.onActiveModelChanged(id),
                                  ),
                                if (hiddenCount > 0)
                                  _AiProviderOverflowChip(
                                    hiddenCount: hiddenCount,
                                    onPressed: _toggleModelChipsExpanded,
                                    tooltip: _localizedText(
                                      ctx,
                                      zh: '展开剩余 $hiddenCount 个模型',
                                      en: 'Show $hiddenCount more models',
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A 4 px primary-tinted bar at the top edge of the settings pane that
/// fades+slides in for ~140 ms and then drains over ~520 ms each time
/// the controller's [SettingsController.saveSuccessSignal] increments.
/// Provides positive confirmation that "your tweak landed" without
/// stealing focus or layout space (overlaid via Stack/IgnorePointer).
/// Thin settings-panel adapter around the shared `HighlightPulse`.
/// Pre-existing call sites pass a `ValueListenable<int>` (the
/// controller's `saveSuccessSignal`) and expect a 3 px top-edge bar.
class _SettingsSavePulse extends StatelessWidget {
  const _SettingsSavePulse({required this.signal});

  final ValueListenable<int> signal;

  @override
  Widget build(BuildContext context) {
    return HighlightPulse(signal: signal);
  }
}

/// 给整数滑杆补一个无障碍微调入口：
///   - 焦点在滑杆上时按 ←/→ 触发 ±[step]，并发一次轻微 [HapticFeedback.selectionClick]
///   - 鼠标点击仍走 [Slider.onChanged]，行为不变
/// 用法：包一层 `KeyTweakableSlider(value:..., min:..., max:..., onChanged:...)`，
/// `_buildSlider` 闭包负责把 value 透传到内部 [Slider]，避免每个调用点都重写 Focus
/// + onKeyEvent 样板。
///
/// 真身已抽到 `lib/shared/ui/key_tweakable_slider.dart`，这里仅保留注释作历史索引。

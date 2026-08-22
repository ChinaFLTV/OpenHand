import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../app/state/settings_controller.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/animated_menu.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../../../shared/ui/openhand_tooltip_dismissal.dart';
import '../../../shared/ui/reorder_proxy_decorator.dart';
import '../../../shared/util/localized_text.dart';
import '../../ai/index.dart';
import '../../settings/index.dart'
    show AiUsageAnalyticsView, showAiModelEditorDialog;
import '../ai_model_proxy_controller.dart';
import '../model/ai_model_proxy_models.dart';
import 'service_dialog_controls.dart';

Future<void> showAiModelProxyProvidersDialog(BuildContext context) =>
    showAnimatedDialog<void>(
      context: context,
      builder: (_) => buildOpenHandDialog(
        maxWidth: kOpenHandDialogWidthWide,
        maxHeight: kOpenHandDialogHeightTall,
        child: const _ProxyProvidersDialog(),
      ),
    );

Future<void> showAiModelProxyModelsDialog(BuildContext context) =>
    showAnimatedDialog<void>(
      context: context,
      builder: (_) => buildOpenHandDialog(
        maxWidth: kOpenHandDialogWidthExtraWide,
        maxHeight: kOpenHandDialogHeightTall,
        child: const _ProxyModelsDialog(),
      ),
    );

Future<void> showAiModelProxySettingsDialog(BuildContext context) =>
    showAnimatedDialog<void>(
      context: context,
      builder: (_) => buildOpenHandDialog(
        maxWidth: kOpenHandDialogWidthWide,
        maxHeight: kOpenHandDialogHeightTall,
        child: const _ProxySettingsDialog(),
      ),
    );

Future<void> showAiModelProxyUsageDialog(BuildContext context) =>
    showAnimatedDialog<void>(
      context: context,
      builder: (_) => buildOpenHandDialog(
        maxWidth: kOpenHandDialogWidthExtraWide,
        maxHeight: kOpenHandDialogHeightTall,
        child: const _ProxyUsageDialog(),
      ),
    );

class _ProxyDialogHeader extends StatelessWidget {
  const _ProxyDialogHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onClose,
    this.actions = const <Widget>[],
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onClose;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: colors.onPrimaryContainer),
        ),
        kOpenHandHGap12,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleLarge),
              kOpenHandGap4,
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        ...actions,
        const SizedBox(width: 8),
        _RoundHeaderButton(
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          icon: Icons.close_rounded,
          onPressed: onClose,
        ),
      ],
    );
  }
}

class _RoundHeaderButton extends StatelessWidget {
  const _RoundHeaderButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.primary = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon),
        style: IconButton.styleFrom(
          backgroundColor: primary
              ? colors.primary
              : colors.surfaceContainerHighest,
          foregroundColor: primary ? colors.onPrimary : colors.onSurfaceVariant,
          shape: const CircleBorder(),
        ),
      ),
    );
  }
}

class _ProxyProvidersDialog extends StatelessWidget {
  const _ProxyProvidersDialog();

  Future<void> _add(BuildContext context) async {
    final settings = context.read<SettingsController>();
    final existing = settings.aiModels.map((item) => item.id).toSet();
    final saved = await showAiModelEditorDialog(context);
    if (!context.mounted || !saved) return;
    final models = settings.aiModels;
    final createdIndex = models.indexWhere(
      (item) => !existing.contains(item.id),
    );
    if (createdIndex > 0) await settings.moveAiModel(createdIndex, 0);
  }

  @override
  Widget build(BuildContext context) {
    final text = openHandTextResolver(context);
    final settings = context.watch<SettingsController>();
    final models = settings.aiModels;
    return ServiceDialogInteractionTheme(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
        child: Column(
          children: [
            _ProxyDialogHeader(
              title: text(zh: 'AI 模型提供商', en: 'AI model providers'),
              subtitle: text(
                zh: '拖动条目调整优先级，越靠前越优先。模型配置与全局设置保持一致。',
                en: 'Drag providers to change priority. Configuration is shared with Settings.',
              ),
              icon: Icons.hub_outlined,
              onClose: () => Navigator.of(context).pop(),
              actions: [
                _RoundHeaderButton(
                  tooltip: text(zh: '新增提供商', en: 'Add provider'),
                  icon: Icons.add_rounded,
                  primary: true,
                  onPressed: () => _add(context),
                ),
                const SizedBox(width: 8),
                _RoundHeaderButton(
                  tooltip: text(zh: '模型映射', en: 'Model routing'),
                  icon: Icons.account_tree_outlined,
                  onPressed: () => showAiModelProxyModelsDialog(context),
                ),
              ],
            ),
            kOpenHandGap16,
            Expanded(
              child: models.isEmpty
                  ? Center(
                      child: Text(
                        text(
                          zh: '还没有提供商配置，请先新增。',
                          en: 'Add a provider to get started.',
                        ),
                      ),
                    )
                  : ReorderableListView.builder(
                      buildDefaultDragHandles: false,
                      itemCount: models.length,
                      onReorder: (oldIndex, newIndex) async {
                        final target = newIndex > oldIndex
                            ? newIndex - 1
                            : newIndex;
                        dismissOpenHandTooltipsSafely(
                          debugLabel: '模型提供商重排前收起工具提示',
                        );
                        await settings.moveAiModel(oldIndex, target);
                      },
                      proxyDecorator: (child, index, animation) =>
                          buildOpenHandReorderProxy(context, child, animation),
                      itemBuilder: (context, index) {
                        final model = models[index];
                        return _ProviderTile(
                          key: ValueKey<String>(model.id),
                          index: index,
                          model: model,
                          onEdit: () => showAiModelEditorDialog(
                            context,
                            initialModel: model,
                          ),
                          onDelete: () {
                            dismissOpenHandTooltipsSafely(
                              debugLabel: '删除模型提供商前收起工具提示',
                            );
                            return settings.deleteAiModel(model.id);
                          },
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

class _ProviderTile extends StatelessWidget {
  const _ProviderTile({
    super.key,
    required this.index,
    required this.model,
    required this.onEdit,
    required this.onDelete,
  });

  final int index;
  final AiModelConfig model;
  final VoidCallback onEdit;
  final Future<bool> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = Theme.of(context).colorScheme;
    final text = openHandTextResolver(context);
    final isDraggingProxy = OpenHandReorderProxyContext.isProxy(context);
    final allModels = model.allModelIds;
    final visibleModels = allModels.take(8).toList(growable: false);
    final hiddenCount = allModels.length - visibleModels.length;
    final card = Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDraggingProxy
            ? Colors.transparent
            : colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(kOpenHandRadius24),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: colors.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${index + 1}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: colors.onPrimaryContainer,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    kOpenHandHGap14,
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            model.providerLabel,
                            style: theme.textTheme.titleLarge,
                          ),
                          kOpenHandGap4,
                          Text(
                            '${model.protocolType.storageValue} · ${text(zh: '模型 ${allModels.length} 个', en: '${allModels.length} models')}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          if (model.modelId.trim().isNotEmpty) ...[
                            kOpenHandGap4,
                            Text(
                              text(
                                zh: '当前模型：${model.modelId}',
                                en: 'Active: ${model.modelId}',
                              ),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              kOpenHandHGap12,
              Wrap(
                spacing: 4,
                children: [
                  _ProxySemanticIconButton(
                    label: text(zh: '编辑', en: 'Edit'),
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  _ProxySemanticIconButton(
                    label: text(zh: '删除', en: 'Delete'),
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                  _ProxyReorderHandle(
                    index: index,
                    label: text(zh: '拖动排序', en: 'Reorder'),
                    child: IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.drag_indicator_rounded),
                    ),
                  ),
                ],
              ),
            ],
          ),
          kOpenHandGap14,
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _ProxyProviderInfoChip(
                icon: Icons.link_rounded,
                label: model.normalizedBaseUrl,
              ),
              _ProxyProviderInfoChip(
                icon: model.autoCompleteBaseUrl
                    ? Icons.auto_fix_high_rounded
                    : Icons.rule_rounded,
                label: model.autoCompleteBaseUrl
                    ? text(zh: '自动补全', en: 'Auto-complete')
                    : text(zh: '精确 Base URL', en: 'Exact Base URL'),
              ),
              _ProxyProviderInfoChip(
                icon: Icons.vpn_key_outlined,
                label: model.maskedToken.isEmpty
                    ? text(zh: '无 Token', en: 'No token')
                    : model.maskedToken,
              ),
              _ProxyProviderInfoChip(
                icon: Icons.route_rounded,
                label: model.apiDialect.storageValue,
              ),
            ],
          ),
          if (visibleModels.isNotEmpty) ...[
            kOpenHandGap10,
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final modelId in visibleModels)
                  _ProxyModelChip(
                    modelId: modelId,
                    active: modelId == model.modelId,
                  ),
                if (hiddenCount > 0)
                  _ProxyModelChip(modelId: '+$hiddenCount', active: false),
              ],
            ),
          ],
        ],
      ),
    );
    return card;
  }
}

class _ProxyReorderHandle extends StatelessWidget {
  const _ProxyReorderHandle({
    required this.index,
    required this.label,
    required this.child,
  });

  final int index;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Listener(
        onPointerDown: (_) =>
            dismissOpenHandTooltipsSafely(debugLabel: '开始拖动模型提供商前收起工具提示'),
        child: ReorderableDragStartListener(index: index, child: child),
      ),
    );
  }
}

class _ProxySemanticIconButton extends StatelessWidget {
  const _ProxySemanticIconButton({
    required this.label,
    required this.onPressed,
    required this.icon,
  });

  final String label;
  final VoidCallback onPressed;
  final Widget icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: IconButton(onPressed: onPressed, icon: icon),
    );
  }
}

class _ProxyProviderInfoChip extends StatelessWidget {
  const _ProxyProviderInfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(maxWidth: 360),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: colors.onSurfaceVariant),
          kOpenHandHGap8,
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

class _ProxyModelChip extends StatelessWidget {
  const _ProxyModelChip({required this.modelId, required this.active});

  final String modelId;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: active
            ? colors.primaryContainer
            : colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: active ? colors.primary : colors.outlineVariant,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            active ? Icons.star_rounded : Icons.smart_toy_outlined,
            size: 16,
            color: active ? colors.primary : colors.onSurfaceVariant,
          ),
          kOpenHandHGap6,
          Text(modelId, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _ProxyModelsDialog extends StatefulWidget {
  const _ProxyModelsDialog();

  @override
  State<_ProxyModelsDialog> createState() => _ProxyModelsDialogState();
}

class _ProxyModelsDialogState extends State<_ProxyModelsDialog> {
  String? _selectedModel;

  static const double _nodeHeight = 72;
  static const double _backendHeight = 82;
  static const double _nodeGap = 12;
  static const double _diagramTopPadding = 18;

  @override
  Widget build(BuildContext context) {
    final text = openHandTextResolver(context);
    final settings = context.watch<SettingsController>();
    final proxy = context.watch<AiModelProxyController>();
    final routes = proxy.settings.routes;
    final exposedModels = <String>{
      ...routes.map((item) => item.exposedModel),
      for (final provider in settings.aiModels) ...provider.allModelIds,
    }.where((item) => item.trim().isNotEmpty).toList()..sort();
    final selected =
        _selectedModel != null && exposedModels.contains(_selectedModel)
        ? _selectedModel!
        : (exposedModels.isEmpty ? null : exposedModels.first);
    final route = selected == null
        ? null
        : routes.where((item) => item.exposedModel == selected).firstOrNull;
    final middleCount = math.max(exposedModels.length, 1);
    final backendCount = math.max(route?.backends.length ?? 0, 1);
    final backendContentHeight =
        backendCount * _backendHeight + (backendCount - 1) * _nodeGap + 12 + 48;
    final diagramHeight = math.max(
      420.0,
      _diagramTopPadding * 2 +
          math.max(
            middleCount * _nodeHeight + (middleCount - 1) * _nodeGap,
            backendContentHeight,
          ),
    );
    final selectedIndex = selected == null
        ? 0
        : exposedModels.indexOf(selected);
    final selectedCenter =
        _diagramTopPadding +
        _nodeHeight / 2 +
        math.max(selectedIndex, 0) * (_nodeHeight + _nodeGap);
    return ServiceDialogInteractionTheme(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
        child: Column(
          children: [
            _ProxyDialogHeader(
              title: text(zh: '模型映射', en: 'Model routing map'),
              subtitle: text(
                zh: '左侧是 OpenHand，中间是 /models 暴露模型，右侧是可调度的后备模型。',
                en: 'OpenHand routes exposed /models entries to one or more provider backends.',
              ),
              icon: Icons.account_tree_outlined,
              onClose: () => Navigator.of(context).pop(),
            ),
            kOpenHandGap18,
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const diagramWidth = 980.0;
                  final width = math.max(diagramWidth, constraints.maxWidth);
                  return SingleChildScrollView(
                    physics: openHandDialogAwareScrollPhysics(context),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: openHandDialogAwareScrollPhysics(context),
                      child: SizedBox(
                        width: width,
                        height: diagramHeight,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              width: 188,
                              child: Center(
                                child: _MindMapNode(
                                  title: text(zh: 'OpenHand', en: 'OpenHand'),
                                  icon: Icons.apps_rounded,
                                  primary: true,
                                ),
                              ),
                            ),
                            _MindMapConnector(
                              height: diagramHeight,
                              sourceY: diagramHeight / 2,
                              branchCount: exposedModels.length,
                              branchTop: _diagramTopPadding,
                              branchHeight: _nodeHeight,
                              gap: _nodeGap,
                              color: Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.56),
                            ),
                            SizedBox(
                              width: 272,
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  top: _diagramTopPadding,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    for (final model in exposedModels) ...[
                                      SizedBox(
                                        height: _nodeHeight,
                                        child: _MindMapNode(
                                          title: model,
                                          icon: Icons.api_rounded,
                                          selected: model == selected,
                                          onTap: () => setState(
                                            () => _selectedModel = model,
                                          ),
                                        ),
                                      ),
                                      if (model != exposedModels.last)
                                        const SizedBox(height: _nodeGap),
                                    ],
                                    if (exposedModels.isEmpty)
                                      _EmptyBackendCard(
                                        text: text(
                                          zh: '暂无可暴露模型',
                                          en: 'No exposed models',
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            _MindMapConnector(
                              height: diagramHeight,
                              sourceY: selectedCenter,
                              branchCount: route?.backends.length ?? 0,
                              branchTop: _diagramTopPadding,
                              branchHeight: _backendHeight,
                              gap: _nodeGap,
                              color: Theme.of(
                                context,
                              ).colorScheme.tertiary.withValues(alpha: 0.62),
                            ),
                            SizedBox(
                              width: 392,
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  top: _diagramTopPadding,
                                ),
                                child: route == null
                                    ? Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          _EmptyBackendCard(
                                            text: text(
                                              zh: selected == null
                                                  ? '选择一个暴露模型查看后备模型。'
                                                  : '该模型还没有后备模型。',
                                              en: selected == null
                                                  ? 'Select an exposed model.'
                                                  : 'This model has no backends yet.',
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          FilledButton.tonalIcon(
                                            onPressed: selected == null
                                                ? null
                                                : () => _addBackend(
                                                    context,
                                                    selected,
                                                  ),
                                            icon: const Icon(Icons.add_rounded),
                                            label: Text(
                                              text(
                                                zh: '添加后备模型',
                                                en: 'Add backend',
                                              ),
                                            ),
                                          ),
                                        ],
                                      )
                                    : Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          for (final (index, backend)
                                              in route.backends.indexed) ...[
                                            SizedBox(
                                              height: _backendHeight,
                                              child: _BackendTile(
                                                backend: backend,
                                                settings: settings,
                                                onToggle: (enabled) =>
                                                    _updateBackend(
                                                      selected!,
                                                      index,
                                                      backend.copyWith(
                                                        enabled: enabled,
                                                      ),
                                                    ),
                                                onRemove: () => _removeBackend(
                                                  selected!,
                                                  index,
                                                ),
                                              ),
                                            ),
                                            if (index !=
                                                route.backends.length - 1)
                                              const SizedBox(height: _nodeGap),
                                          ],
                                          if (route.backends.isEmpty)
                                            _EmptyBackendCard(
                                              text: text(
                                                zh: '暂无后备模型',
                                                en: 'No backends',
                                              ),
                                            ),
                                          const SizedBox(height: 12),
                                          FilledButton.tonalIcon(
                                            onPressed: selected == null
                                                ? null
                                                : () => _addBackend(
                                                    context,
                                                    selected,
                                                  ),
                                            icon: const Icon(Icons.add_rounded),
                                            label: Text(
                                              text(
                                                zh: '添加后备模型',
                                                en: 'Add backend',
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addBackend(BuildContext context, String exposedModel) async {
    final settings = context.read<SettingsController>();
    final proxy = context.read<AiModelProxyController>();
    final currentRoute = proxy.settings.routes
        .where((item) => item.exposedModel == exposedModel)
        .firstOrNull;
    final existing = {
      for (final backend
          in currentRoute?.backends ?? const <AiModelProxyBackend>[])
        '${backend.providerId}\u0000${backend.modelId}',
    };
    final candidates =
        <({String providerId, String providerName, String modelId})>[
          for (final provider in settings.aiModels)
            for (final modelId in provider.allModelIds)
              if (!existing.contains('${provider.id}\u0000$modelId'))
                (
                  providerId: provider.id,
                  providerName: provider.displayName,
                  modelId: modelId,
                ),
        ];
    final chosen =
        await showAnimatedDialog<({String providerId, String modelId})>(
          context: context,
          builder: (_) => _BackendPickerDialog(candidates: candidates),
        );
    if (!context.mounted || chosen == null) return;
    final current = proxy.settings.routes;
    final index = current.indexWhere(
      (item) => item.exposedModel == exposedModel,
    );
    final route = index < 0
        ? AiModelProxyRoute(
            exposedModel: exposedModel,
            backends: [
              AiModelProxyBackend(
                providerId: chosen.providerId,
                modelId: chosen.modelId,
              ),
            ],
          )
        : current[index].copyWith(
            backends: [
              ...current[index].backends,
              AiModelProxyBackend(
                providerId: chosen.providerId,
                modelId: chosen.modelId,
              ),
            ],
          );
    final next = List<AiModelProxyRoute>.of(current);
    if (index < 0) {
      next.add(route);
    } else {
      next[index] = route;
    }
    await proxy.saveRoutes(next);
  }

  Future<void> _updateBackend(
    String exposedModel,
    int backendIndex,
    AiModelProxyBackend backend,
  ) async {
    final proxy = context.read<AiModelProxyController>();
    final routeIndex = proxy.settings.routes.indexWhere(
      (item) => item.exposedModel == exposedModel,
    );
    if (routeIndex < 0) return;
    final route = proxy.settings.routes[routeIndex];
    if (backendIndex < 0 || backendIndex >= route.backends.length) return;
    final backends = List<AiModelProxyBackend>.of(route.backends);
    backends[backendIndex] = backend;
    final routes = List<AiModelProxyRoute>.of(proxy.settings.routes);
    routes[routeIndex] = route.copyWith(backends: backends);
    await proxy.saveRoutes(routes);
  }

  Future<void> _removeBackend(String exposedModel, int backendIndex) async {
    final proxy = context.read<AiModelProxyController>();
    final routeIndex = proxy.settings.routes.indexWhere(
      (item) => item.exposedModel == exposedModel,
    );
    if (routeIndex < 0) return;
    final route = proxy.settings.routes[routeIndex];
    if (backendIndex < 0 || backendIndex >= route.backends.length) return;
    final backends = List<AiModelProxyBackend>.of(route.backends)
      ..removeAt(backendIndex);
    final routes = List<AiModelProxyRoute>.of(proxy.settings.routes);
    routes[routeIndex] = route.copyWith(backends: backends);
    await proxy.saveRoutes(routes);
  }
}

class _MindMapConnector extends StatelessWidget {
  const _MindMapConnector({
    required this.height,
    required this.sourceY,
    required this.branchCount,
    required this.branchTop,
    required this.branchHeight,
    required this.gap,
    required this.color,
  });

  final double height;
  final double sourceY;
  final int branchCount;
  final double branchTop;
  final double branchHeight;
  final double gap;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 56,
    height: height,
    child: CustomPaint(
      painter: _MindMapConnectorPainter(
        sourceY: sourceY,
        branchCount: branchCount,
        branchTop: branchTop,
        branchHeight: branchHeight,
        gap: gap,
        color: color,
      ),
    ),
  );
}

class _MindMapConnectorPainter extends CustomPainter {
  const _MindMapConnectorPainter({
    required this.sourceY,
    required this.branchCount,
    required this.branchTop,
    required this.branchHeight,
    required this.gap,
    required this.color,
  });

  final double sourceY;
  final int branchCount;
  final double branchTop;
  final double branchHeight;
  final double gap;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final spineX = size.width / 2;
    final source = sourceY.clamp(0.0, size.height).toDouble();
    canvas.drawLine(Offset(0, source), Offset(spineX, source), paint);
    if (branchCount <= 0) {
      canvas.drawLine(
        Offset(spineX, source),
        Offset(size.width, source),
        paint,
      );
      return;
    }
    final centers = List<double>.generate(
      branchCount,
      (index) => branchTop + branchHeight / 2 + index * (branchHeight + gap),
      growable: false,
    );
    final first = centers.first.clamp(0.0, size.height).toDouble();
    final last = centers.last.clamp(0.0, size.height).toDouble();
    canvas.drawLine(Offset(spineX, first), Offset(spineX, last), paint);
    for (final center in centers) {
      final y = center.clamp(0.0, size.height).toDouble();
      canvas.drawLine(Offset(spineX, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_MindMapConnectorPainter oldDelegate) =>
      oldDelegate.sourceY != sourceY ||
      oldDelegate.branchCount != branchCount ||
      oldDelegate.branchTop != branchTop ||
      oldDelegate.branchHeight != branchHeight ||
      oldDelegate.gap != gap ||
      oldDelegate.color != color;
}

class _MindMapNode extends StatelessWidget {
  const _MindMapNode({
    required this.title,
    required this.icon,
    this.primary = false,
    this.selected = false,
    this.onTap,
  });
  final String title;
  final IconData icon;
  final bool primary;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final child = Container(
      constraints: const BoxConstraints(minHeight: 62),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: primary
            ? colors.primaryContainer
            : selected
            ? colors.primaryContainer
            : colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected ? colors.primary : colors.outlineVariant,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: primary ? colors.onPrimaryContainer : colors.primary,
          ),
          kOpenHandHGap10,
          Expanded(
            child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
    return onTap == null
        ? child
        : InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: child,
          );
  }
}

class _EmptyBackendCard extends StatelessWidget {
  const _EmptyBackendCard({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(kOpenHandRadius16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Text(text),
    );
  }
}

class _BackendTile extends StatelessWidget {
  const _BackendTile({
    required this.backend,
    required this.settings,
    required this.onToggle,
    required this.onRemove,
  });
  final AiModelProxyBackend backend;
  final SettingsController settings;
  final ValueChanged<bool> onToggle;
  final VoidCallback onRemove;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final provider = settings.aiModels
        .where((item) => item.id == backend.providerId)
        .firstOrNull;
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: backend.enabled
            ? colors.primaryContainer.withValues(alpha: 0.72)
            : colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(kOpenHandRadius16),
        border: Border.all(
          color: backend.enabled ? colors.primary : colors.outlineVariant,
        ),
      ),
      child: Row(
        children: [
          Icon(
            backend.enabled
                ? Icons.check_circle_rounded
                : Icons.pause_circle_outline_rounded,
            color: backend.enabled ? colors.primary : colors.onSurfaceVariant,
          ),
          kOpenHandHGap10,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  backend.modelId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                kOpenHandGap4,
                Text(
                  provider?.displayName ?? backend.providerId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Switch(value: backend.enabled, onChanged: onToggle),
          ServiceDialogCompactIconButton(
            tooltip: openHandLocalizedText(
              context,
              zh: '移除后备模型',
              en: 'Remove backend',
            ),
            icon: const Icon(Icons.close_rounded, size: 20),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _BackendPickerDialog extends StatelessWidget {
  const _BackendPickerDialog({required this.candidates});
  final List<({String providerId, String providerName, String modelId})>
  candidates;
  @override
  Widget build(BuildContext context) => buildOpenHandDialog(
    maxWidth: kOpenHandDialogWidthStandard,
    maxHeight: kOpenHandDialogHeightTall,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Text(
            openHandLocalizedText(context, zh: '选择后备模型', en: 'Choose backend'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          kOpenHandGap12,
          Expanded(
            child: ListView(
              children: [
                if (candidates.isEmpty)
                  _EmptyBackendCard(
                    text: openHandLocalizedText(
                      context,
                      zh: '没有可添加的后备模型。请先配置其他提供商或模型。',
                      en: 'No backend candidates. Add another provider or model first.',
                    ),
                  )
                else
                  for (final item in candidates)
                    ListTile(
                      leading: const Icon(Icons.cloud_outlined),
                      title: Text(item.modelId),
                      subtitle: Text(item.providerName),
                      onTap: () => Navigator.of(context).pop((
                        providerId: item.providerId,
                        modelId: item.modelId,
                      )),
                    ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _ProxySettingsDialog extends StatefulWidget {
  const _ProxySettingsDialog();
  @override
  State<_ProxySettingsDialog> createState() => _ProxySettingsDialogState();
}

class _ProxySettingsDialogState extends State<_ProxySettingsDialog> {
  late bool _auth;
  late AiModelProxyApiStyle _style;
  late AiModelProxyLimitMode _limitMode;
  late AiModelProxyRetryPolicy _retry;
  late AiModelProxySchedulingStrategy _scheduling;
  late int _threshold;
  late int _retryCount;
  late TextEditingController _key;

  @override
  void initState() {
    super.initState();
    final value = context.read<AiModelProxyController>().settings;
    _auth = value.requireAuthentication;
    _style = value.apiStyle;
    _limitMode = value.limitMode;
    _retry = value.retryPolicy;
    _scheduling = value.scheduling;
    _threshold = value.limitThreshold;
    _retryCount = value.retryCount;
    _key = TextEditingController(text: value.apiKey);
  }

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final controller = context.read<AiModelProxyController>();
    await controller.saveSettings(
      controller.settings.copyWith(
        requireAuthentication: _auth,
        apiKey: _key.text.trim(),
        apiStyle: _style,
        limitMode: _limitMode,
        limitThreshold: _threshold,
        retryPolicy: _retry,
        retryCount: _retryCount,
        scheduling: _scheduling,
      ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final text = openHandTextResolver(context);
    return ServiceDialogInteractionTheme(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
        child: Column(
          children: [
            _ProxyDialogHeader(
              title: text(zh: '服务设置', en: 'Service settings'),
              subtitle: text(
                zh: '配置对外协议、鉴权、限流与故障接力策略。',
                en: 'Configure protocol, authentication, limits and failover.',
              ),
              icon: Icons.tune_rounded,
              onClose: () => Navigator.of(context).pop(),
            ),
            kOpenHandGap16,
            Expanded(
              child: ListView(
                children: [
                  _ProxyToggleRow(
                    value: _auth,
                    onChanged: (value) => setState(() => _auth = value),
                    title: text(zh: 'API 鉴权', en: 'API authentication'),
                    subtitle: text(
                      zh: '启用后请求必须携带与 API 风格一致的 Key。',
                      en: 'Require a matching API key on incoming requests.',
                    ),
                  ),
                  if (_auth) ...[
                    kOpenHandGap8,
                    TextField(
                      controller: _key,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: text(zh: 'API Key', en: 'API key'),
                      ),
                    ),
                  ],
                  kOpenHandGap14,
                  _DropdownField<AiModelProxyApiStyle>(
                    label: text(zh: 'API 风格', en: 'API style'),
                    value: _style,
                    values: AiModelProxyApiStyle.values,
                    labelOf: (item) => item.label,
                    onChanged: (value) => setState(() => _style = value),
                  ),
                  kOpenHandGap12,
                  _DropdownField<AiModelProxyLimitMode>(
                    label: text(zh: '并发限制方式', en: 'Rate limit mode'),
                    value: _limitMode,
                    values: AiModelProxyLimitMode.values,
                    labelOf: (item) => item.label,
                    onChanged: (value) => setState(() => _limitMode = value),
                  ),
                  kOpenHandGap12,
                  _NumberStepper(
                    label:
                        '${_limitMode.label} ${text(zh: '阈值', en: 'threshold')}',
                    value: _threshold,
                    min: 1,
                    max: 1000000,
                    onChanged: (value) => setState(() => _threshold = value),
                  ),
                  kOpenHandGap12,
                  _DropdownField<AiModelProxyRetryPolicy>(
                    label: text(zh: '重试策略', en: 'Retry policy'),
                    value: _retry,
                    values: AiModelProxyRetryPolicy.values,
                    labelOf: (item) => item.label,
                    onChanged: (value) => setState(() => _retry = value),
                  ),
                  if (_retry != AiModelProxyRetryPolicy.failFast) ...[
                    kOpenHandGap12,
                    _NumberStepper(
                      label: text(zh: '重试次数', en: 'Retry count'),
                      value: _retryCount,
                      min: 1,
                      max: 10,
                      onChanged: (value) => setState(() => _retryCount = value),
                    ),
                  ],
                  if (_retry == AiModelProxyRetryPolicy.retryAndFailover) ...[
                    kOpenHandGap12,
                    _DropdownField<AiModelProxySchedulingStrategy>(
                      label: text(zh: '服务商调度策略', en: 'Provider scheduling'),
                      value: _scheduling,
                      values: AiModelProxySchedulingStrategy.values,
                      labelOf: (item) => item.label,
                      onChanged: (value) => setState(() => _scheduling = value),
                    ),
                  ],
                ],
              ),
            ),
            kOpenHandGap14,
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OpenHandDialogActionButton.secondary(
                  label: text(zh: '取消', en: 'Cancel'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                kOpenHandHGap10,
                OpenHandDialogActionButton.primary(
                  onPressed: _save,
                  icon: Icons.save_outlined,
                  label: text(zh: '保存设置', en: 'Save settings'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DropdownField<T> extends StatelessWidget {
  const _DropdownField({
    required this.label,
    required this.value,
    required this.values,
    required this.labelOf,
    required this.onChanged,
  });
  final String label;
  final T value;
  final List<T> values;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<T>(
    initialValue: value,
    decoration: InputDecoration(labelText: label),
    items: [
      for (final item in values)
        DropdownMenuItem<T>(value: item, child: Text(labelOf(item))),
    ],
    onChanged: (next) {
      if (next != null) onChanged(next);
    },
  );
}

class _NumberStepper extends StatefulWidget {
  const _NumberStepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });
  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  State<_NumberStepper> createState() => _NumberStepperState();
}

class _NumberStepperState extends State<_NumberStepper> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.value}');
    _focusNode = FocusNode();
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant _NumberStepper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value &&
        !_focusNode.hasFocus &&
        _controller.text != '${widget.value}') {
      _setControllerValue(widget.value);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (!_focusNode.hasFocus && int.tryParse(_controller.text.trim()) == null) {
      _setControllerValue(widget.value);
    }
  }

  void _setControllerValue(int value) {
    final text = '$value';
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _commit(String raw) {
    final parsed = int.tryParse(raw.trim());
    if (parsed == null) return;
    final next = parsed.clamp(widget.min, widget.max).toInt();
    if (_controller.text != '$next') _setControllerValue(next);
    widget.onChanged(next);
  }

  void _changeBy(int delta) {
    final next = (widget.value + delta).clamp(widget.min, widget.max).toInt();
    _setControllerValue(next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InputDecorator(
      decoration: InputDecoration(
        labelText: widget.label,
        contentPadding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: IconButton.filledTonal(
              onPressed: widget.value <= widget.min
                  ? null
                  : () => _changeBy(-1),
              icon: const Icon(Icons.remove_rounded),
              tooltip: openHandLocalizedText(context, zh: '减少', en: 'Decrease'),
              style: IconButton.styleFrom(
                foregroundColor: colors.onPrimaryContainer,
                backgroundColor: colors.primaryContainer,
                disabledForegroundColor: colors.onSurface.withValues(
                  alpha: 0.38,
                ),
                disabledBackgroundColor: colors.surfaceContainerHighest,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 52,
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                textAlign: TextAlign.center,
                textInputAction: TextInputAction.done,
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                style: Theme.of(context).textTheme.titleMedium,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: colors.surfaceContainerLow,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(kOpenHandRadius12),
                    borderSide: BorderSide(color: colors.outlineVariant),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(kOpenHandRadius12),
                    borderSide: BorderSide(color: colors.outlineVariant),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(kOpenHandRadius12),
                    borderSide: BorderSide(color: colors.primary, width: 2),
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                ),
                onChanged: _commit,
                onSubmitted: _commit,
                onEditingComplete: () {
                  if (int.tryParse(_controller.text.trim()) == null) {
                    _setControllerValue(widget.value);
                  } else {
                    _commit(_controller.text);
                  }
                  _focusNode.unfocus();
                },
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 48,
            height: 48,
            child: IconButton.filledTonal(
              onPressed: widget.value >= widget.max ? null : () => _changeBy(1),
              icon: const Icon(Icons.add_rounded),
              tooltip: openHandLocalizedText(context, zh: '增加', en: 'Increase'),
              style: IconButton.styleFrom(
                foregroundColor: colors.onPrimaryContainer,
                backgroundColor: colors.primaryContainer,
                disabledForegroundColor: colors.onSurface.withValues(
                  alpha: 0.38,
                ),
                disabledBackgroundColor: colors.surfaceContainerHighest,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProxyToggleRow extends StatelessWidget {
  const _ProxyToggleRow({
    required this.value,
    required this.onChanged,
    required this.title,
    required this.subtitle,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 10, 14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(kOpenHandRadius16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                kOpenHandGap4,
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            thumbIcon: WidgetStateProperty.resolveWith<Icon?>((states) {
              if (states.contains(WidgetState.selected)) {
                return const Icon(Icons.check_rounded, size: 16);
              }
              return const Icon(Icons.close_rounded, size: 16);
            }),
            trackColor: WidgetStateProperty.resolveWith((states) {
              return states.contains(WidgetState.selected)
                  ? colors.primary
                  : colors.surfaceContainerHighest;
            }),
            trackOutlineColor: WidgetStatePropertyAll(colors.outlineVariant),
          ),
        ],
      ),
    );
  }
}

class _ProxyUsageDialog extends StatefulWidget {
  const _ProxyUsageDialog();

  @override
  State<_ProxyUsageDialog> createState() => _ProxyUsageDialogState();
}

class _ProxyUsageDialogState extends State<_ProxyUsageDialog> {
  AiUsageDataScope _scope = AiUsageDataScope.proxyOnly;

  @override
  Widget build(BuildContext context) {
    final text = openHandTextResolver(context);
    final proxy = context.watch<AiModelProxyController>();
    final stats = proxy.settings;
    final records = stats.recentRequests;
    return ServiceDialogInteractionTheme(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ProxyDialogHeader(
              title: text(zh: '使用统计', en: 'Usage analytics'),
              subtitle: text(
                zh: '汇总请求、成功率、Token、成本与耗时，保留全局追踪的详细记录。',
                en: 'Requests, success rate, tokens, cost and latency with global traces.',
              ),
              icon: Icons.query_stats_rounded,
              onClose: () => Navigator.of(context).pop(),
              actions: [
                AnimatedPopupMenuButton<AiUsageDataScope>(
                  tooltip: text(zh: '过滤统计范围', en: 'Filter data scope'),
                  initialValue: _scope,
                  onSelected: (value) => setState(() => _scope = value),
                  icon: const Icon(Icons.filter_alt_outlined),
                  itemBuilder: (context) => [
                    _scopeMenuItem(
                      context,
                      AiUsageDataScope.proxyOnly,
                      '仅展示中转站统计数据',
                      'Proxy only',
                    ),
                    _scopeMenuItem(
                      context,
                      AiUsageDataScope.nonProxy,
                      '仅展示非中转站统计数据',
                      'Non-proxy only',
                    ),
                    _scopeMenuItem(
                      context,
                      AiUsageDataScope.all,
                      '展示所有统计数据',
                      'All statistics',
                    ),
                  ],
                ),
              ],
            ),
            kOpenHandGap16,
            Flexible(
              child: SingleChildScrollView(
                physics: openHandDialogAwareScrollPhysics(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AiUsageAnalyticsView(
                      key: ValueKey<AiUsageDataScope>(_scope),
                      embedded: true,
                      initialFilter: AiUsageFilter(scope: _scope),
                    ),
                    if (_scope == AiUsageDataScope.proxyOnly) ...[
                      kOpenHandGap16,
                      _ProxyServiceTraceExtension(
                        records: records,
                        requestCount: stats.requestCount,
                        successRate: stats.successRate,
                        totalTokens: stats.totalTokens,
                        averageDurationMs: stats.averageDurationMs,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<AiUsageDataScope> _scopeMenuItem(
    BuildContext context,
    AiUsageDataScope value,
    String zh,
    String en,
  ) {
    return PopupMenuItem<AiUsageDataScope>(
      value: value,
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: _scope == value
                ? const Icon(Icons.check_rounded, size: 18)
                : null,
          ),
          Text(openHandLocalizedText(context, zh: zh, en: en)),
        ],
      ),
    );
  }
}

class _ProxyServiceTraceExtension extends StatelessWidget {
  const _ProxyServiceTraceExtension({
    required this.records,
    required this.requestCount,
    required this.successRate,
    required this.totalTokens,
    required this.averageDurationMs,
  });

  final List<AiModelProxyRequestRecord> records;
  final int requestCount;
  final double successRate;
  final int totalTokens;
  final double averageDurationMs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = openHandTextResolver(context);
    final recent = records.reversed.take(12).toList(growable: false);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(kOpenHandRadius20),
        border: Border.all(color: colors.outlineVariant),
      ),
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
                      text(zh: '请求追踪', en: 'Request traces'),
                      style: theme.textTheme.titleLarge,
                    ),
                    kOpenHandGap4,
                    Text(
                      text(
                        zh: '记录实际服务商、模型、协议、Token、耗时与失败原因。',
                        en: 'Inspect provider, model, protocol, tokens, latency and errors.',
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              _ProxyTraceBadge(
                label: text(
                  zh: '最近 ${recent.length} 条',
                  en: '${recent.length} recent',
                ),
              ),
            ],
          ),
          kOpenHandGap14,
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _Metric(
                label: text(zh: '请求数', en: 'Requests'),
                value: '$requestCount',
              ),
              _Metric(
                label: text(zh: '成功率', en: 'Success rate'),
                value: '${(successRate * 100).toStringAsFixed(1)}%',
              ),
              _Metric(
                label: text(zh: 'Token', en: 'Tokens'),
                value: '$totalTokens',
              ),
              _Metric(
                label: text(zh: '平均耗时', en: 'Average latency'),
                value: '${averageDurationMs.toStringAsFixed(1)} ms',
              ),
            ],
          ),
          kOpenHandGap16,
          if (recent.isEmpty)
            _ProxyTraceEmpty(
              text: text(
                zh: '暂无中转请求记录，启动服务并完成请求后会在这里显示。',
                en: 'No proxy requests yet. Traces appear after the service handles a request.',
              ),
            )
          else
            Column(
              children: [
                for (final record in recent) _ProxyRecordTile(record: record),
              ],
            ),
        ],
      ),
    );
  }
}

class _ProxyTraceBadge extends StatelessWidget {
  const _ProxyTraceBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: colors.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ProxyTraceEmpty extends StatelessWidget {
  const _ProxyTraceEmpty({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(kOpenHandRadius16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Text(text, style: TextStyle(color: colors.onSurfaceVariant)),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(kOpenHandRadius16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          kOpenHandGap4,
          Text(value, style: theme.textTheme.titleLarge),
        ],
      ),
    );
  }
}

class _ProxyRecordTile extends StatelessWidget {
  const _ProxyRecordTile({required this.record});

  final AiModelProxyRequestRecord record;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        leading: Icon(
          record.success
              ? Icons.check_circle_outline_rounded
              : Icons.error_outline_rounded,
          color: record.success ? colors.primary : colors.error,
        ),
        title: Text('${record.providerId} / ${record.modelId}'),
        subtitle: Text(
          '${record.apiStyle} · ${record.tokens} tokens · ${record.durationMs} ms'
          '${record.proxyMode.isEmpty ? '' : ' · ${record.proxyMode}'}'
          '${record.proxyEndpoint.isEmpty ? '' : ' · ${record.proxyEndpoint}'}'
          '${record.clientIp.isEmpty ? '' : ' · ${record.clientIp}${record.clientPort.isEmpty ? '' : ':${record.clientPort}'}'}'
          '${record.error == null ? '' : ' · ${record.error}'}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Text(record.startedAt.toLocal().toString().substring(0, 16)),
      ),
    );
  }
}

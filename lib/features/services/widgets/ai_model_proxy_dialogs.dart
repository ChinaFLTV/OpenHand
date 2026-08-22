import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../app/state/settings_controller.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/ui/animated_appearance.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/animated_menu.dart';
import '../../../shared/ui/list_removal_transition.dart';
import '../../../shared/ui/model_search_selector.dart';
import '../../../shared/ui/motion_preference.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../../../shared/ui/openhand_tooltip_dismissal.dart';
import '../../../shared/ui/reorder_proxy_decorator.dart';
import '../../../shared/util/localized_text.dart';
import '../../ai/index.dart';
import '../../settings/index.dart'
    show
        AiUsageAnalyticsView,
        buildAiModelProviderCard,
        showAiModelEditorDialog,
        showAiModelProfileEditorDialog,
        testAiModelConfiguration;
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
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon),
        style: IconButton.styleFrom(
          backgroundColor: colors.surfaceContainerHighest,
          foregroundColor: colors.onSurfaceVariant,
          shape: const CircleBorder(),
        ),
      ),
    );
  }
}

class _ProxyProvidersDialog extends StatefulWidget {
  const _ProxyProvidersDialog();

  @override
  State<_ProxyProvidersDialog> createState() => _ProxyProvidersDialogState();
}

class _ProxyProvidersDialogState extends State<_ProxyProvidersDialog> {
  final Set<String> _mutatingIds = <String>{};
  final Set<String> _removingIds = <String>{};
  final Set<String> _testingIds = <String>{};

  Future<void> _add(BuildContext context) async {
    final settings = context.read<SettingsController>();
    final existing = settings.aiModels.map((item) => item.id).toSet();
    final saved = await showAiModelEditorDialog(context);
    if (!context.mounted || !saved) return;
    final createdIndex = settings.aiModels.indexWhere(
      (item) => !existing.contains(item.id),
    );
    if (createdIndex > 0) await settings.moveAiModel(createdIndex, 0);
  }

  Future<void> _move(AiModelConfig model, int direction) async {
    if (_mutatingIds.isNotEmpty || !mounted) return;
    final settings = context.read<SettingsController>();
    final index = settings.aiModels.indexWhere((item) => item.id == model.id);
    final target = index + direction;
    if (index < 0 || target < 0 || target >= settings.aiModels.length) return;
    setState(() => _mutatingIds.add(model.id));
    var moved = false;
    try {
      moved = await settings.moveAiModel(index, target);
    } catch (_) {
      moved = false;
    }
    if (!mounted) return;
    setState(() => _mutatingIds.remove(model.id));
    if (!moved) {
      showOpenHandErrorSnack(
        context,
        AppLocalizations.of(context)!.settingsPersistenceSaveFailedBody,
      );
    }
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    if (_mutatingIds.isNotEmpty) return;
    if (newIndex > oldIndex) newIndex -= 1;
    final settings = context.read<SettingsController>();
    if (oldIndex < 0 ||
        newIndex < 0 ||
        oldIndex >= settings.aiModels.length ||
        newIndex >= settings.aiModels.length ||
        oldIndex == newIndex) {
      return;
    }
    dismissOpenHandTooltipsSafely(debugLabel: '拖动模型提供商前收起工具提示');
    final model = settings.aiModels[oldIndex];
    setState(() => _mutatingIds.add(model.id));
    var moved = false;
    try {
      moved = await settings.moveAiModel(oldIndex, newIndex);
    } catch (_) {
      moved = false;
    }
    if (!mounted) return;
    setState(() => _mutatingIds.remove(model.id));
    if (!moved) {
      showOpenHandErrorSnack(
        context,
        AppLocalizations.of(context)!.settingsPersistenceSaveFailedBody,
      );
    }
  }

  Future<void> _delete(AiModelConfig model) async {
    if (_mutatingIds.isNotEmpty) return;
    final text = openHandTextResolver(context);
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: text(zh: '删除模型提供商', en: 'Delete model provider'),
      message: text(
        zh: '确认删除“${model.providerLabel}”吗？',
        en: 'Delete “${model.providerLabel}”?',
      ),
      cancelLabel: openHandCancelLabel(context),
      confirmLabel: text(zh: '删除', en: 'Delete'),
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final settings = context.read<SettingsController>();
    setState(() {
      _mutatingIds.add(model.id);
      _removingIds.add(model.id);
    });
    await awaitOpenHandListRemoval(context);
    if (!mounted) return;
    var deleted = false;
    try {
      deleted = await settings.deleteAiModel(model.id);
    } catch (_) {
      deleted = false;
    }
    if (!mounted) return;
    setState(() {
      _mutatingIds.remove(model.id);
      _removingIds.remove(model.id);
    });
    if (deleted) {
      flashOpenHandSnack(
        context,
        text(zh: '模型提供商配置已删除。', en: 'Provider deleted.'),
        kind: OpenHandSnackKind.success,
      );
    } else {
      showOpenHandErrorSnack(
        context,
        AppLocalizations.of(context)!.settingsPersistenceSaveFailedBody,
      );
    }
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
                      onReorder: _reorder,
                      proxyDecorator: (child, index, animation) =>
                          buildOpenHandReorderProxy(context, child, animation),
                      itemBuilder: (context, index) {
                        final model = models[index];
                        final enabled = !_mutatingIds.contains(model.id);
                        return KeyedSubtree(
                          key: ValueKey<String>(model.id),
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: OpenHandListRemovalTransition(
                              collapsed: _removingIds.contains(model.id),
                              child: buildAiModelProviderCard(
                                model: model,
                                dragIndex: index,
                                isSelected:
                                    settings.selectedAiModelId == model.id,
                                isTesting: _testingIds.contains(model.id),
                                isFirst: index == 0,
                                isLast: index == models.length - 1,
                                actionsEnabled: enabled,
                                onSelect: () =>
                                    settings.updateSelectedAiModel(model.id),
                                onTest: () async {
                                  if (!enabled ||
                                      _testingIds.contains(model.id)) {
                                    return;
                                  }
                                  setState(() => _testingIds.add(model.id));
                                  try {
                                    await testAiModelConfiguration(
                                      context,
                                      model,
                                    );
                                  } finally {
                                    if (mounted) {
                                      setState(
                                        () => _testingIds.remove(model.id),
                                      );
                                    }
                                  }
                                },
                                onEdit: () => showAiModelEditorDialog(
                                  context,
                                  initialModel: model,
                                ),
                                onMoveUp: () => _move(model, -1),
                                onMoveDown: () => _move(model, 1),
                                onDelete: () => _delete(model),
                                onActiveModelChanged: (modelId) =>
                                    settings.updateProviderActiveModel(
                                      model.id,
                                      modelId,
                                      alsoSelectProvider: false,
                                    ),
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
}

class _ProxyModelsDialog extends StatefulWidget {
  const _ProxyModelsDialog();

  @override
  State<_ProxyModelsDialog> createState() => _ProxyModelsDialogState();
}

class _ProxyModelsDialogState extends State<_ProxyModelsDialog> {
  String? _selectedModel;
  late final ScrollController _diagramHorizontalController;

  static const double _nodeHeight = 72;
  static const double _backendHeight = 82;
  static const double _nodeGap = 12;
  static const double _diagramTopPadding = 18;
  static const double _diagramMinWidth = 944;
  static const double _rootColumnWidth = 164;
  static const double _modelColumnWidth = 268;

  @override
  void initState() {
    super.initState();
    _diagramHorizontalController = ScrollController();
  }

  @override
  void dispose() {
    _diagramHorizontalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = openHandTextResolver(context);
    final settings = context.watch<SettingsController>();
    final proxy = context.watch<AiModelProxyController>();
    final routes = proxy.settings.routes;
    final exposedModels = routes
        .map((item) => item.exposedModel.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    final selected =
        _selectedModel != null && exposedModels.contains(_selectedModel)
        ? _selectedModel!
        : (exposedModels.isEmpty ? null : exposedModels.first);
    final route = selected == null
        ? null
        : routes.where((item) => item.exposedModel == selected).firstOrNull;
    final middleCount = math.max(exposedModels.length, 1);
    final backendCount = route?.backends.length ?? 0;
    final backendItemsHeight = backendCount > 0
        ? backendCount * _backendHeight + (backendCount - 1) * _nodeGap
        : 56;
    final backendContentHeight =
        backendItemsHeight + 12 + 48 + (route == null ? 0 : 12 + 96);
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
    final maxBackendTop = math.max(
      _diagramTopPadding,
      diagramHeight - backendContentHeight - _diagramTopPadding,
    );
    final backendTop = (selectedCenter - backendContentHeight / 2).clamp(
      _diagramTopPadding,
      maxBackendTop,
    );
    return ServiceDialogInteractionTheme(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ProxyDialogHeader(
              title: text(zh: '模型映射', en: 'Model routing map'),
              subtitle: text(
                zh: '左侧是 OpenHand，中间是 /models 暴露模型，右侧是可调度的后备模型。',
                en: 'OpenHand routes exposed /models entries to one or more provider backends.',
              ),
              icon: Icons.account_tree_outlined,
              onClose: () => Navigator.of(context).pop(),
              actions: [
                _RoundHeaderButton(
                  tooltip: text(zh: '新增暴露模型', en: 'Add exposed model'),
                  icon: Icons.add_rounded,
                  onPressed: () => _addExposedModel(context),
                ),
              ],
            ),
            kOpenHandGap18,
            Flexible(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = math.max(
                    _diagramMinWidth,
                    constraints.maxWidth.isFinite
                        ? constraints.maxWidth
                        : _diagramMinWidth,
                  );
                  return SingleChildScrollView(
                    physics: openHandDialogAwareScrollPhysics(context),
                    child: SingleChildScrollView(
                      controller: _diagramHorizontalController,
                      primary: false,
                      scrollDirection: Axis.horizontal,
                      physics: openHandDialogAwareScrollPhysics(context),
                      child: SizedBox(
                        width: width,
                        height: diagramHeight,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              width: _rootColumnWidth,
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
                              width: _modelColumnWidth,
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  top: _diagramTopPadding,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _AnimatedMappingItems<String>(
                                      key: const ValueKey<String>(
                                        'proxy-exposed-model-items',
                                      ),
                                      items: exposedModels,
                                      itemKey: (model) => model,
                                      gap: _nodeGap,
                                      emptyChild: Column(
                                        children: [
                                          _EmptyBackendCard(
                                            text: text(
                                              zh: '暂无可暴露模型，请先新增并配置。',
                                              en: 'No exposed models. Add and configure one first.',
                                            ),
                                          ),
                                          kOpenHandGap10,
                                          FilledButton.tonalIcon(
                                            onPressed: () =>
                                                _addExposedModel(context),
                                            icon: const Icon(Icons.add_rounded),
                                            label: Text(
                                              text(
                                                zh: '新增暴露模型',
                                                en: 'Add exposed model',
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      itemBuilder: (model) => SizedBox(
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
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            _MindMapConnector(
                              height: diagramHeight,
                              sourceY: selectedCenter,
                              branchCount: route?.backends.length ?? 0,
                              branchTop: backendTop,
                              branchHeight: _backendHeight,
                              gap: _nodeGap,
                              color: Theme.of(
                                context,
                              ).colorScheme.tertiary.withValues(alpha: 0.62),
                            ),
                            Expanded(
                              child: Padding(
                                padding: EdgeInsets.only(top: backendTop),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _AnimatedMappingItems<AiModelProxyBackend>(
                                      key: const ValueKey<String>(
                                        'proxy-backend-items',
                                      ),
                                      items:
                                          route?.backends ??
                                          const <AiModelProxyBackend>[],
                                      itemKey: (backend) =>
                                          '${backend.providerId.trim()}\u0000${backend.modelId.trim()}',
                                      gap: _nodeGap,
                                      emptyChild: _EmptyBackendCard(
                                        text: text(
                                          zh: selected == null
                                              ? '选择一个暴露模型查看后备模型。'
                                              : '该模型还没有后备模型。',
                                          en: selected == null
                                              ? 'Select an exposed model.'
                                              : 'This model has no backends yet.',
                                        ),
                                      ),
                                      itemBuilder: (backend) {
                                        final backendIndex =
                                            route?.backends.indexOf(backend) ??
                                            -1;
                                        return SizedBox(
                                          height: _backendHeight,
                                          child: _BackendTile(
                                            backend: backend,
                                            settings: settings,
                                            onToggle: (enabled) {
                                              if (selected == null ||
                                                  backendIndex < 0) {
                                                return;
                                              }
                                              _updateBackend(
                                                selected,
                                                backendIndex,
                                                backend.copyWith(
                                                  enabled: enabled,
                                                ),
                                              );
                                            },
                                            onRemove: () {
                                              if (selected == null ||
                                                  backendIndex < 0) {
                                                return;
                                              }
                                              _removeBackend(
                                                selected,
                                                backendIndex,
                                              );
                                            },
                                          ),
                                        );
                                      },
                                    ),
                                    const SizedBox(height: 12),
                                    Align(
                                      alignment:
                                          AlignmentDirectional.centerStart,
                                      child: FilledButton.tonalIcon(
                                        onPressed: selected == null
                                            ? null
                                            : () => _addBackend(
                                                context,
                                                selected,
                                              ),
                                        style: FilledButton.styleFrom(
                                          minimumSize: const Size(0, 42),
                                          maximumSize: const Size(
                                            double.infinity,
                                            42,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                          ),
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        icon: const Icon(Icons.add_rounded),
                                        label: Text(
                                          text(zh: '添加后备模型', en: 'Add backend'),
                                        ),
                                      ),
                                    ),
                                    if (route != null) ...[
                                      const SizedBox(height: 12),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          OutlinedButton.icon(
                                            onPressed: () => _editExposedModel(
                                              context,
                                              route,
                                            ),
                                            icon: const Icon(
                                              Icons.tune_rounded,
                                            ),
                                            label: Text(
                                              text(
                                                zh: '编辑暴露模型参数',
                                                en: 'Edit exposed parameters',
                                              ),
                                            ),
                                          ),
                                          if (route.backends.isNotEmpty)
                                            OutlinedButton.icon(
                                              onPressed: () =>
                                                  _copyBackendProfile(
                                                    context,
                                                    route,
                                                  ),
                                              icon: const Icon(
                                                Icons.content_copy_rounded,
                                              ),
                                              label: Text(
                                                text(
                                                  zh: '复制后备模型参数',
                                                  en: 'Copy backend parameters',
                                                ),
                                              ),
                                            ),
                                          Tooltip(
                                            message: text(
                                              zh: '删除暴露模型',
                                              en: 'Remove exposed model',
                                            ),
                                            child: IconButton.filledTonal(
                                              onPressed: () =>
                                                  _removeExposedModel(
                                                    context,
                                                    route,
                                                  ),
                                              icon: const Icon(
                                                Icons.delete_outline_rounded,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
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

  Future<void> _addExposedModel(BuildContext context) async {
    final text = openHandTextResolver(context);
    final modelId = await showOpenHandTextInputDialog(
      context: context,
      title: text(zh: '新增暴露模型', en: 'Add exposed model'),
      hintText: text(zh: '输入对外暴露的模型 ID', en: 'Exposed model ID'),
      confirmLabel: text(zh: '下一步', en: 'Next'),
      icon: const Icon(Icons.api_rounded),
      maxWidth: 460,
    );
    if (!context.mounted || modelId == null || modelId.isEmpty) return;
    final proxy = context.read<AiModelProxyController>();
    final routes = proxy.settings.routes;
    if (routes.any((route) => route.exposedModel == modelId)) {
      showOpenHandErrorSnack(
        context,
        text(zh: '该暴露模型已存在。', en: 'That exposed model already exists.'),
      );
      return;
    }
    await proxy.saveRoutes([
      ...routes,
      AiModelProxyRoute(exposedModel: modelId, backends: const []),
    ]);
    if (!mounted || !context.mounted) return;
    setState(() => _selectedModel = modelId);
    await _editExposedModel(
      context,
      AiModelProxyRoute(exposedModel: modelId, backends: const []),
    );
  }

  Future<void> _editExposedModel(
    BuildContext context,
    AiModelProxyRoute route,
  ) async {
    final proxy = context.read<AiModelProxyController>();
    final result = await showAiModelProfileEditorDialog(
      context,
      modelId: route.exposedModel,
      initialProfile: route.profile,
      effectiveProfile: route.profile,
      protocolType: _proxyProtocolType(proxy.settings.apiStyle),
      existingModelIds: proxy.settings.routes
          .map((item) => item.exposedModel)
          .toList(growable: false),
    );
    if (!mounted || !context.mounted || result == null) return;
    final nextModelId = result.modelId.trim();
    if (nextModelId.isEmpty) return;
    final currentRoutes = proxy.settings.routes;
    final routeIndex = currentRoutes.indexWhere(
      (item) => item.exposedModel == route.exposedModel,
    );
    if (routeIndex < 0) return;
    if (nextModelId != route.exposedModel &&
        currentRoutes.any((item) => item.exposedModel == nextModelId)) {
      showOpenHandErrorSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '该暴露模型 ID 已存在。',
          en: 'That exposed model ID already exists.',
        ),
      );
      return;
    }
    final nextRoutes = List<AiModelProxyRoute>.of(currentRoutes);
    nextRoutes[routeIndex] = currentRoutes[routeIndex].copyWith(
      exposedModel: nextModelId,
      profile: result.profile,
    );
    await proxy.saveRoutes(nextRoutes);
    if (mounted && nextModelId != route.exposedModel) {
      setState(() => _selectedModel = nextModelId);
    }
  }

  Future<void> _copyBackendProfile(
    BuildContext context,
    AiModelProxyRoute route,
  ) async {
    if (route.backends.isEmpty) return;
    final backend = route.backends.firstWhere(
      (item) => item.enabled,
      orElse: () => route.backends.first,
    );
    final provider = context
        .read<SettingsController>()
        .aiModels
        .where((item) => item.id == backend.providerId)
        .firstOrNull;
    if (provider == null) {
      showOpenHandErrorSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '后备模型提供商已不存在，无法复制参数。',
          en: 'The backend provider no longer exists.',
        ),
      );
      return;
    }
    final proxy = context.read<AiModelProxyController>();
    final routeIndex = proxy.settings.routes.indexWhere(
      (item) => item.exposedModel == route.exposedModel,
    );
    if (routeIndex < 0) return;
    final routes = List<AiModelProxyRoute>.of(proxy.settings.routes);
    routes[routeIndex] = routes[routeIndex].copyWith(
      profile: provider.profileFor(backend.modelId),
    );
    await proxy.saveRoutes(routes);
  }

  Future<void> _removeExposedModel(
    BuildContext context,
    AiModelProxyRoute route,
  ) async {
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: openHandLocalizedText(
        context,
        zh: '删除暴露模型',
        en: 'Remove exposed model',
      ),
      message: openHandLocalizedText(
        context,
        zh: '确认删除“${route.exposedModel}”及其后备模型配置吗？',
        en: 'Remove “${route.exposedModel}” and its backend configuration?',
      ),
      cancelLabel: openHandCancelLabel(context),
      confirmLabel: openHandLocalizedText(context, zh: '删除', en: 'Remove'),
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final proxy = context.read<AiModelProxyController>();
    final routes = proxy.settings.routes
        .where((item) => item.exposedModel != route.exposedModel)
        .toList(growable: false);
    await proxy.saveRoutes(routes);
    if (!mounted) return;
    setState(
      () => _selectedModel = routes.isEmpty ? null : routes.first.exposedModel,
    );
  }

  static AiProtocolType _proxyProtocolType(AiModelProxyApiStyle style) =>
      switch (style) {
        AiModelProxyApiStyle.claude => AiProtocolType.claude,
        AiModelProxyApiStyle.gemini => AiProtocolType.gemini,
        AiModelProxyApiStyle.openAiChatCompletions ||
        AiModelProxyApiStyle.openAiResponses => AiProtocolType.openai,
      };

  Future<void> _addBackend(BuildContext context, String exposedModel) async {
    final settings = context.read<SettingsController>();
    final proxy = context.read<AiModelProxyController>();
    final currentRoute = proxy.settings.routes
        .where((item) => item.exposedModel == exposedModel)
        .firstOrNull;
    final existing = {
      for (final backend
          in currentRoute?.backends ?? const <AiModelProxyBackend>[])
        '${backend.providerId.trim()}\u0000${backend.modelId.trim()}',
    };
    final chosen = await showModelSearchSelector(
      context: context,
      models: settings.aiModels,
      recentSelections: settings.recentModelSelections,
      modelFilter: (config, modelId) =>
          !existing.contains('${config.id.trim()}\u0000${modelId.trim()}'),
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
              AiModelProxyBackend(providerId: chosen.$1, modelId: chosen.$2),
            ],
          )
        : current[index].copyWith(
            backends: [
              ...current[index].backends,
              AiModelProxyBackend(providerId: chosen.$1, modelId: chosen.$2),
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

/// 模型映射图中的动态条目容器：保留已移除条目直到退场动画完成，避免列表
/// 数据变化时卡片瞬间消失；新增条目使用全局弹窗动效自然进入。
class _AnimatedMappingItems<T> extends StatefulWidget {
  const _AnimatedMappingItems({
    super.key,
    required this.items,
    required this.itemKey,
    required this.itemBuilder,
    required this.emptyChild,
    required this.gap,
  });

  final List<T> items;
  final String Function(T item) itemKey;
  final Widget Function(T item) itemBuilder;
  final Widget emptyChild;
  final double gap;

  @override
  State<_AnimatedMappingItems<T>> createState() =>
      _AnimatedMappingItemsState<T>();
}

class _AnimatedMappingItemsState<T> extends State<_AnimatedMappingItems<T>> {
  late List<T> _displayedItems;

  @override
  void initState() {
    super.initState();
    _displayedItems = List<T>.of(widget.items);
  }

  @override
  void didUpdateWidget(covariant _AnimatedMappingItems<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final currentKeys = widget.items.map(widget.itemKey).toSet();
    final nextDisplayed = List<T>.of(widget.items);
    for (var index = 0; index < _displayedItems.length; index++) {
      final previous = _displayedItems[index];
      if (!currentKeys.contains(widget.itemKey(previous))) {
        nextDisplayed.insert(index.clamp(0, nextDisplayed.length), previous);
      }
    }
    _displayedItems = nextDisplayed;
  }

  void _removeDismissed(String itemKey) {
    if (widget.items.any((item) => widget.itemKey(item) == itemKey)) return;
    if (!mounted) return;
    setState(() {
      _displayedItems.removeWhere((item) => widget.itemKey(item) == itemKey);
    });
  }

  @override
  Widget build(BuildContext context) {
    final motionSettings = openHandMotionSettingsOf(
      context,
      OpenHandMotionSettingsScope.dialog,
    );
    final currentKeys = widget.items.map(widget.itemKey).toSet();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in _displayedItems)
          AnimatedAppearance(
            key: ValueKey<String>('proxy-mapping-item-${widget.itemKey(item)}'),
            settings: motionSettings,
            present: currentKeys.contains(widget.itemKey(item)),
            onDismissed: () => _removeDismissed(widget.itemKey(item)),
            child: IgnorePointer(
              ignoring: !currentKeys.contains(widget.itemKey(item)),
              child: Padding(
                padding: EdgeInsets.only(bottom: widget.gap),
                child: widget.itemBuilder(item),
              ),
            ),
          ),
        AnimatedAppearance(
          key: const ValueKey<String>('proxy-mapping-empty-item'),
          settings: motionSettings,
          present: widget.items.isEmpty,
          child: widget.emptyChild,
        ),
      ],
    );
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
    canvas.drawLine(Offset(spineX, source), Offset(spineX, first), paint);
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

class _ProxySettingsDialog extends StatefulWidget {
  const _ProxySettingsDialog();
  @override
  State<_ProxySettingsDialog> createState() => _ProxySettingsDialogState();
}

class _ProxySettingsDialogState extends State<_ProxySettingsDialog> {
  late final TextEditingController _listenHost;
  late bool _auth;
  late AiModelProxyApiStyle _style;
  late AiModelProxyLimitMode _limitMode;
  late AiModelProxyRetryPolicy _retry;
  late AiModelProxySchedulingStrategy _scheduling;
  late int _threshold;
  late int _retryCount;
  late int _listenPort;
  late TextEditingController _key;

  @override
  void initState() {
    super.initState();
    final value = context.read<AiModelProxyController>().settings;
    _listenHost = TextEditingController(text: value.listenHost);
    _listenPort = value.listenPort;
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
    _listenHost.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final controller = context.read<AiModelProxyController>();
    await controller.saveSettings(
      controller.settings.copyWith(
        listenHost: _listenHost.text.trim().isEmpty
            ? aiModelProxyDefaultListenHost
            : _listenHost.text.trim(),
        listenPort: _listenPort,
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
                  TextField(
                    controller: _listenHost,
                    textInputAction: TextInputAction.next,
                    keyboardType: TextInputType.text,
                    decoration: InputDecoration(
                      labelText: text(zh: '监听地址', en: 'Listen address'),
                      prefixIcon: const Icon(Icons.lan_outlined),
                      helperText: text(
                        zh: '默认 $aiModelProxyDefaultListenHost，仅本机访问。',
                        en: 'Default $aiModelProxyDefaultListenHost; local access only.',
                      ),
                    ),
                  ),
                  kOpenHandGap12,
                  _NumberStepper(
                    label: text(zh: '监听端口', en: 'Listen port'),
                    value: _listenPort,
                    min: aiModelProxyMinListenPort,
                    max: aiModelProxyMaxListenPort,
                    onChanged: (value) => setState(() => _listenPort = value),
                  ),
                  kOpenHandGap14,
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

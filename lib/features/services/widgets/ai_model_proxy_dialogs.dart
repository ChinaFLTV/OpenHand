import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../app/model/dialog_animation_settings.dart';
import '../../../app/state/settings_controller.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/ui/animated_appearance.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/animated_menu.dart';
import '../../../shared/ui/feature_state_card.dart';
import '../../../shared/ui/list_removal_transition.dart';
import '../../../shared/ui/model_search_selector.dart';
import '../../../shared/ui/motion_durations.dart';
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
import '../ai_model_health_controller.dart';
import '../ai_model_proxy_controller.dart';
import '../model/ai_model_proxy_models.dart';
import 'ai_model_health_widgets.dart';
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
  final VoidCallback? onPressed;

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
          disabledBackgroundColor: colors.surfaceContainerLow,
          disabledForegroundColor: colors.onSurface.withValues(alpha: 0.38),
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
            Expanded(
              child: ReorderableListView.builder(
                buildDefaultDragHandles: false,
                padding: const EdgeInsets.only(bottom: 14),
                header: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AiModelHealthSettingsPanel(showRequestMode: true),
                    kOpenHandGap16,
                    if (models.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 18),
                        child: Text(
                          text(
                            zh: '还没有提供商配置，请先新增。',
                            en: 'Add a provider to get started.',
                          ),
                        ),
                      ),
                  ],
                ),
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
                          isSelected: settings.selectedAiModelId == model.id,
                          isTesting: _testingIds.contains(model.id),
                          isFirst: index == 0,
                          isLast: index == models.length - 1,
                          actionsEnabled: enabled,
                          onSelect: () =>
                              settings.updateSelectedAiModel(model.id),
                          onTest: () async {
                            if (!enabled || _testingIds.contains(model.id)) {
                              return;
                            }
                            setState(() => _testingIds.add(model.id));
                            try {
                              await testAiModelConfiguration(context, model);
                            } finally {
                              if (mounted) {
                                setState(() => _testingIds.remove(model.id));
                              }
                            }
                          },
                          onHealthCheck: () => context
                              .read<AiModelHealthController>()
                              .checkProvider(model),
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
  bool _isClearing = false;
  int _displayedExposedModelCount = 0;
  int _displayedBackendItemCount = 0;
  String? _displayedBackendGroupKey;
  int _sourceBackendItemCount = 0;
  List<AiModelProxyRoute>? _cachedRoutesSource;
  Map<String, AiModelProxyRoute> _cachedRoutesByKey =
      const <String, AiModelProxyRoute>{};
  List<String> _cachedExposedModels = const <String>[];
  List<AiModelConfig>? _cachedProvidersSource;
  Map<String, AiModelConfig> _cachedProvidersByKey =
      const <String, AiModelConfig>{};
  late final ScrollController _diagramVerticalController;
  late final ScrollController _diagramHorizontalController;

  static const double _nodeHeight = 96;
  static const double _backendHeight = 96;
  static const double _nodeGap = 12;
  static const double _diagramTopPadding = 18;
  static const double _diagramMinWidth = 860;
  static const double _connectorWidth = 56;
  static const double _modelColumnWidth = 392;
  static const double _backendColumnWidth = 360;
  // 空状态卡片包含 18px 内边距和 1px 边框，实际高度为 58px。
  static const double _emptyBackendCardHeight = 58;
  static const double _backendActionHeight = 42;

  static String _modelKey(String value) => value.trim().toLowerCase();

  static String _backendKey(AiModelProxyBackend backend) =>
      '${backend.providerId.trim().toLowerCase()}\u0000${backend.modelId.trim().toLowerCase()}';

  @override
  void initState() {
    super.initState();
    _diagramVerticalController = ScrollController();
    _diagramHorizontalController = ScrollController();
  }

  @override
  void dispose() {
    _diagramVerticalController.dispose();
    _diagramHorizontalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = openHandTextResolver(context);
    final colors = Theme.of(context).colorScheme;
    final modelProviders = context
        .select<SettingsController, List<AiModelConfig>>(
          (controller) => controller.aiModels,
        );
    final routes = context
        .select<AiModelProxyController, List<AiModelProxyRoute>>(
          (controller) => controller.settings.routes,
        );
    if (!identical(_cachedRoutesSource, routes)) {
      final previousExposedModelCount = _cachedExposedModels.length;
      final routesByKey = <String, AiModelProxyRoute>{};
      for (final item in routes) {
        final key = _modelKey(item.exposedModel);
        if (key.isNotEmpty) routesByKey.putIfAbsent(key, () => item);
      }
      _cachedRoutesSource = routes;
      _cachedRoutesByKey = routesByKey;
      _cachedExposedModels = List<String>.unmodifiable(
        routesByKey.values.map((item) => item.exposedModel),
      );
      // 删除时子列表还要保留旧卡片播放退场动画，父级高度同步保留旧数量，
      // 避免新数据先收缩导致最后一项溢出。
      _displayedExposedModelCount = math.max(
        _displayedExposedModelCount,
        math.max(previousExposedModelCount, _cachedExposedModels.length),
      );
    }
    final routesByKey = _cachedRoutesByKey;
    final exposedModels = _cachedExposedModels;
    final activeModel =
        routesByKey[_modelKey(_selectedModel ?? '')]?.exposedModel ??
        exposedModels.firstOrNull;
    final route = activeModel == null
        ? null
        : routesByKey[_modelKey(activeModel)];
    final backendItems = <AiModelProxyBackend>[];
    final backendKeys = <String>{};
    final backendIndexes = <String, int>{};
    for (final (index, backend)
        in (route?.backends ?? const <AiModelProxyBackend>[]).indexed) {
      final key = _backendKey(backend);
      if (backendKeys.add(key)) backendItems.add(backend);
      backendIndexes.putIfAbsent(key, () => index);
    }
    final backendGroupKey = _modelKey(activeModel ?? '');
    if (_displayedBackendGroupKey != backendGroupKey) {
      _displayedBackendGroupKey = backendGroupKey;
      _sourceBackendItemCount = backendItems.length;
      _displayedBackendItemCount = backendItems.length;
    } else {
      _displayedBackendItemCount = math.max(
        _displayedBackendItemCount,
        _sourceBackendItemCount,
      );
      _sourceBackendItemCount = backendItems.length;
    }
    if (!identical(_cachedProvidersSource, modelProviders)) {
      _cachedProvidersSource = modelProviders;
      _cachedProvidersByKey = <String, AiModelConfig>{
        for (final provider in modelProviders)
          provider.id.trim().toLowerCase(): provider,
      };
    }
    final providersByKey = _cachedProvidersByKey;
    final middleCount = math.max(
      math.max(exposedModels.length, _displayedExposedModelCount),
      1,
    );
    final backendCount = backendItems.length;
    final displayedBackendCount = math.max(
      backendCount,
      _displayedBackendItemCount,
    );
    final backendItemsHeight = displayedBackendCount > 0
        ? displayedBackendCount * (_backendHeight + _nodeGap)
        : _emptyBackendCardHeight;
    final backendContentHeight =
        backendItemsHeight +
        (displayedBackendCount > 0 ? 0 : _nodeGap) +
        _backendActionHeight;
    final diagramHeight = math.max(
      420.0,
      _diagramTopPadding * 2 +
          math.max(
            middleCount * (_nodeHeight + _nodeGap),
            backendContentHeight,
          ),
    );
    final selectedIndex = activeModel == null
        ? 0
        : exposedModels.indexWhere(
            (model) => _modelKey(model) == _modelKey(activeModel),
          );
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
                zh: '左侧是 /models 暴露模型，右侧是按所选策略调度的后备模型。',
                en: 'Exposed /models entries route by the selected backend strategy.',
              ),
              icon: Icons.account_tree_outlined,
              onClose: () => Navigator.of(context).pop(),
              actions: [
                _RoundHeaderButton(
                  tooltip: text(zh: '新增暴露模型', en: 'Add exposed model'),
                  icon: Icons.add_rounded,
                  onPressed: _isClearing
                      ? null
                      : () => _addExposedModel(context),
                ),
                const SizedBox(width: 8),
                _RoundHeaderButton(
                  tooltip: text(zh: '清空暴露模型', en: 'Clear exposed models'),
                  icon: Icons.delete_sweep_rounded,
                  onPressed: exposedModels.isEmpty || _isClearing
                      ? null
                      : () => _clearExposedModels(context),
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
                  final viewportHeight = math.min(
                    constraints.maxHeight.isFinite
                        ? constraints.maxHeight
                        : double.infinity,
                    MediaQuery.sizeOf(context).height * 0.7,
                  );
                  return SingleChildScrollView(
                    controller: _diagramHorizontalController,
                    scrollDirection: Axis.horizontal,
                    physics: openHandDialogAwareScrollPhysics(context),
                    child: SizedBox(
                      width: width,
                      height: viewportHeight,
                      child: Stack(
                        children: [
                          if (exposedModels.isEmpty &&
                              _displayedExposedModelCount == 0)
                            Positioned.fill(
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  top: _diagramTopPadding,
                                ),
                                child: FeatureStateCard.centered(
                                  icon: Icons.account_tree_outlined,
                                  tone: FeatureStateTone.neutral,
                                  title: text(
                                    zh: '暂无暴露模型',
                                    en: 'No exposed models',
                                  ),
                                  body: text(
                                    zh: '点击右上角“新增暴露模型”按钮开始配置。',
                                    en: 'Click “Add exposed model” in the top-right corner to get started.',
                                  ),
                                ),
                              ),
                            )
                          else
                            Positioned(
                              left: 0,
                              top: 0,
                              width: _modelColumnWidth,
                              bottom: 0,
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  top: _diagramTopPadding,
                                ),
                                child: _AnimatedMappingItems<String>(
                                  key: const ValueKey<String>(
                                    'proxy-exposed-model-items',
                                  ),
                                  items: exposedModels,
                                  itemKey: (model) => model,
                                  gap: _nodeGap,
                                  itemExtent: _nodeHeight + _nodeGap,
                                  scrollController: _diagramVerticalController,
                                  scrollPadding: EdgeInsets.only(
                                    bottom: math.max(
                                      0,
                                      diagramHeight -
                                          _diagramTopPadding -
                                          middleCount *
                                              (_nodeHeight + _nodeGap),
                                    ),
                                  ),
                                  scrollPhysics:
                                      openHandDialogAwareScrollPhysics(context),
                                  onDisplayItemsChanged:
                                      _updateDisplayedExposedModelCount,
                                  emptyChild: const SizedBox.shrink(),
                                  onReorder: _reorderExposedModels,
                                  itemBuilder: (model) {
                                    final modelRoute =
                                        routesByKey[_modelKey(model)];
                                    return SizedBox(
                                      width: _modelColumnWidth,
                                      height: _nodeHeight,
                                      child: _ProxyMappingCard(
                                        title: model,
                                        subtitle: text(
                                          zh: '对外暴露模型',
                                          en: 'Exposed model',
                                        ),
                                        enabled: modelRoute?.enabled ?? true,
                                        selected:
                                            _modelKey(model) ==
                                            _modelKey(activeModel ?? ''),
                                        onTap: () => _selectModel(model),
                                        onToggle: modelRoute == null
                                            ? null
                                            : (enabled) => _toggleExposedModel(
                                                model,
                                                enabled,
                                              ),
                                        onEdit: modelRoute == null
                                            ? null
                                            : () => _editExposedModel(
                                                context,
                                                modelRoute,
                                              ),
                                        onRemove: modelRoute == null
                                            ? null
                                            : () => _removeExposedModel(
                                                context,
                                                modelRoute,
                                              ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          if (exposedModels.isNotEmpty) ...[
                            AnimatedBuilder(
                              animation: _diagramVerticalController,
                              child: IgnorePointer(
                                child: _MindMapConnector(
                                  height: diagramHeight,
                                  sourceY: selectedCenter,
                                  branchCount: displayedBackendCount,
                                  branchTop: backendTop,
                                  branchCenterY: displayedBackendCount == 0
                                      ? backendTop + _emptyBackendCardHeight / 2
                                      : null,
                                  branchHeight: _backendHeight,
                                  gap: _nodeGap,
                                  color: Theme.of(context).colorScheme.tertiary
                                      .withValues(alpha: 0.62),
                                ),
                              ),
                              builder: (context, child) {
                                final scrollOffset =
                                    _diagramVerticalController.hasClients
                                    ? _diagramVerticalController.offset
                                    : 0.0;
                                return Positioned(
                                  left: _modelColumnWidth,
                                  top: -scrollOffset,
                                  width: _connectorWidth,
                                  height: diagramHeight,
                                  child: child!,
                                );
                              },
                            ),
                            AnimatedBuilder(
                              animation: _diagramVerticalController,
                              child: SizedBox(
                                width: _backendColumnWidth,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _AnimatedMappingItems<AiModelProxyBackend>(
                                      key: ValueKey<String>(
                                        'proxy-backend-items-${_modelKey(activeModel ?? '')}',
                                      ),
                                      displayGroupKey: _modelKey(
                                        activeModel ?? '',
                                      ),
                                      items: backendItems,
                                      itemKey: (backend) =>
                                          '${backend.providerId.trim()}\u0000${backend.modelId.trim()}',
                                      gap: _nodeGap,
                                      itemExtent: _backendHeight + _nodeGap,
                                      onDisplayItemsChanged:
                                          _updateDisplayedBackendItemCount,
                                      onReorder: activeModel == null
                                          ? null
                                          : (oldIndex, newIndex) =>
                                                _reorderBackends(
                                                  activeModel,
                                                  oldIndex,
                                                  newIndex,
                                                ),
                                      emptyChild: _EmptyBackendCard(
                                        text: text(
                                          zh: activeModel == null
                                              ? '选择一个暴露模型查看后备模型。'
                                              : '该模型还没有后备模型。',
                                          en: activeModel == null
                                              ? 'Select an exposed model.'
                                              : 'This model has no backends yet.',
                                        ),
                                      ),
                                      itemBuilder: (backend) {
                                        final backendIndex =
                                            backendIndexes[_backendKey(
                                              backend,
                                            )] ??
                                            -1;
                                        final provider =
                                            providersByKey[backend.providerId
                                                .trim()
                                                .toLowerCase()];
                                        return SizedBox(
                                          width: _backendColumnWidth,
                                          height: _backendHeight,
                                          child: _ProxyMappingCard(
                                            title: backend.modelId,
                                            subtitle:
                                                provider?.displayName ??
                                                backend.providerId,
                                            enabled: backend.enabled,
                                            onToggle:
                                                activeModel == null ||
                                                    backendIndex < 0
                                                ? null
                                                : (enabled) => _updateBackend(
                                                    activeModel,
                                                    backendIndex,
                                                    backend.copyWith(
                                                      enabled: enabled,
                                                    ),
                                                  ),
                                            onEdit:
                                                activeModel == null ||
                                                    backendIndex < 0
                                                ? null
                                                : () => _editBackendModel(
                                                    context,
                                                    activeModel,
                                                    backend,
                                                    backendIndex,
                                                  ),
                                            onRemove:
                                                activeModel == null ||
                                                    backendIndex < 0
                                                ? null
                                                : () => _removeBackend(
                                                    context,
                                                    activeModel,
                                                    backend,
                                                  ),
                                          ),
                                        );
                                      },
                                    ),
                                    if (displayedBackendCount == 0)
                                      const SizedBox(height: _nodeGap),
                                    Align(
                                      alignment:
                                          AlignmentDirectional.centerStart,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          FilledButton.tonalIcon(
                                            onPressed:
                                                activeModel == null ||
                                                    _isClearing
                                                ? null
                                                : () => _addBackend(
                                                    context,
                                                    activeModel,
                                                  ),
                                            style: FilledButton.styleFrom(
                                              minimumSize: const Size(0, 42),
                                              maximumSize: const Size(
                                                double.infinity,
                                                42,
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 16,
                                                  ),
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                            ),
                                            icon: const Icon(Icons.add_rounded),
                                            label: Text(
                                              text(
                                                zh: '添加后备模型',
                                                en: 'Add backend',
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          FilledButton.tonalIcon(
                                            onPressed:
                                                activeModel == null ||
                                                    backendItems.isEmpty ||
                                                    _isClearing
                                                ? null
                                                : () => _clearBackends(
                                                    context,
                                                    activeModel,
                                                  ),
                                            style: FilledButton.styleFrom(
                                              minimumSize: const Size(0, 42),
                                              maximumSize: const Size(
                                                double.infinity,
                                                42,
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 14,
                                                  ),
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                              backgroundColor: colors
                                                  .errorContainer
                                                  .withValues(alpha: 0.78),
                                              foregroundColor:
                                                  colors.onErrorContainer,
                                            ),
                                            icon: const Icon(
                                              Icons.delete_sweep_rounded,
                                            ),
                                            label: Text(
                                              text(
                                                zh: '清空后备模型',
                                                en: 'Clear backends',
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              builder: (context, child) {
                                final scrollOffset =
                                    _diagramVerticalController.hasClients
                                    ? _diagramVerticalController.offset
                                    : 0.0;
                                return Positioned(
                                  left: _modelColumnWidth + _connectorWidth,
                                  top: backendTop - scrollOffset,
                                  width: _backendColumnWidth,
                                  height: backendContentHeight,
                                  child: child!,
                                );
                              },
                            ),
                          ],
                        ],
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

  void _updateDisplayedExposedModelCount(int count) {
    if (!mounted || _displayedExposedModelCount == count) return;
    setState(() => _displayedExposedModelCount = count);
  }

  void _updateDisplayedBackendItemCount(int count) {
    if (!mounted || _displayedBackendItemCount == count) return;
    setState(() => _displayedBackendItemCount = count);
  }

  void _selectModel(String model) {
    final canonicalModel =
        _cachedRoutesByKey[_modelKey(model)]?.exposedModel ?? model;
    if (_modelKey(_selectedModel ?? '') == _modelKey(canonicalModel)) return;
    setState(() => _selectedModel = canonicalModel);
  }

  Future<void> _clearExposedModels(BuildContext context) async {
    if (_isClearing || !mounted) return;
    final proxy = context.read<AiModelProxyController>();
    if (proxy.settings.routes.isEmpty) return;
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: openHandLocalizedText(
        context,
        zh: '清空暴露模型',
        en: 'Clear exposed models',
      ),
      message: openHandLocalizedText(
        context,
        zh: '确认清空全部暴露模型及其对应的后备模型配置吗？此操作不可撤销。',
        en: 'Clear all exposed models and their backend configurations? This cannot be undone.',
      ),
      cancelLabel: openHandCancelLabel(context),
      confirmLabel: openHandLocalizedText(context, zh: '清空', en: 'Clear'),
      destructive: true,
    );
    if (!confirmed || !mounted || !context.mounted) return;
    setState(() => _isClearing = true);
    try {
      if (await _persistRoutes(const <AiModelProxyRoute>[])) {
        if (!mounted || !context.mounted) return;
        setState(() => _selectedModel = null);
        flashOpenHandSnack(
          context,
          openHandLocalizedText(
            context,
            zh: '已清空全部暴露模型及其后备模型配置。',
            en: 'All exposed models and backend configurations were cleared.',
          ),
          kind: OpenHandSnackKind.success,
        );
      }
    } finally {
      if (mounted) setState(() => _isClearing = false);
    }
  }

  Future<void> _clearBackends(BuildContext context, String exposedModel) async {
    if (_isClearing || !mounted) return;
    final proxy = context.read<AiModelProxyController>();
    final route = proxy.settings.routes
        .where(
          (item) => _modelKey(item.exposedModel) == _modelKey(exposedModel),
        )
        .firstOrNull;
    if (route == null || route.backends.isEmpty) return;
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: openHandLocalizedText(
        context,
        zh: '清空后备模型',
        en: 'Clear backend models',
      ),
      message: openHandLocalizedText(
        context,
        zh: '确认清空“${route.exposedModel}”的全部后备模型吗？此操作不可撤销。',
        en: 'Clear all backend models for “${route.exposedModel}”? This cannot be undone.',
      ),
      cancelLabel: openHandCancelLabel(context),
      confirmLabel: openHandLocalizedText(context, zh: '清空', en: 'Clear'),
      destructive: true,
    );
    if (!confirmed || !mounted || !context.mounted) return;
    setState(() => _isClearing = true);
    try {
      final currentRoutes = proxy.settings.routes;
      final routeIndex = currentRoutes.indexWhere(
        (item) => _modelKey(item.exposedModel) == _modelKey(exposedModel),
      );
      if (routeIndex < 0 || currentRoutes[routeIndex].backends.isEmpty) return;
      final routes = List<AiModelProxyRoute>.of(currentRoutes);
      routes[routeIndex] = routes[routeIndex].copyWith(backends: const []);
      if (!await _persistRoutes(routes) || !mounted || !context.mounted) {
        return;
      }
      flashOpenHandSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '已清空当前暴露模型的后备模型。',
          en: 'Backend models for the selected exposed model were cleared.',
        ),
        kind: OpenHandSnackKind.success,
      );
    } finally {
      if (mounted) setState(() => _isClearing = false);
    }
  }

  Future<void> _toggleExposedModel(String exposedModel, bool enabled) async {
    final proxy = context.read<AiModelProxyController>();
    final routeIndex = proxy.settings.routes.indexWhere(
      (item) => _modelKey(item.exposedModel) == _modelKey(exposedModel),
    );
    if (routeIndex < 0) return;
    final routes = List<AiModelProxyRoute>.of(proxy.settings.routes);
    routes[routeIndex] = routes[routeIndex].copyWith(enabled: enabled);
    await _persistRoutes(routes);
  }

  void _reorderExposedModels(int oldIndex, int newIndex) {
    final proxy = context.read<AiModelProxyController>();
    final routes = List<AiModelProxyRoute>.of(proxy.settings.routes);
    if (newIndex > oldIndex) newIndex -= 1;
    if (oldIndex < 0 ||
        newIndex < 0 ||
        oldIndex >= routes.length ||
        newIndex >= routes.length ||
        oldIndex == newIndex) {
      return;
    }
    dismissOpenHandTooltipsSafely(debugLabel: '拖动暴露模型前收起工具提示');
    final route = routes.removeAt(oldIndex);
    routes.insert(newIndex, route);
    unawaited(_persistReorderedRoutes(routes));
  }

  void _reorderBackends(String exposedModel, int oldIndex, int newIndex) {
    final proxy = context.read<AiModelProxyController>();
    final routeIndex = proxy.settings.routes.indexWhere(
      (item) => _modelKey(item.exposedModel) == _modelKey(exposedModel),
    );
    if (routeIndex < 0) return;
    final route = proxy.settings.routes[routeIndex];
    if (newIndex > oldIndex) newIndex -= 1;
    if (oldIndex < 0 ||
        newIndex < 0 ||
        oldIndex >= route.backends.length ||
        newIndex >= route.backends.length ||
        oldIndex == newIndex) {
      return;
    }
    dismissOpenHandTooltipsSafely(debugLabel: '拖动后备模型前收起工具提示');
    final backends = List<AiModelProxyBackend>.of(route.backends);
    final backend = backends.removeAt(oldIndex);
    backends.insert(newIndex, backend);
    final routes = List<AiModelProxyRoute>.of(proxy.settings.routes);
    routes[routeIndex] = route.copyWith(backends: backends);
    unawaited(_persistReorderedRoutes(routes));
  }

  Future<void> _persistReorderedRoutes(List<AiModelProxyRoute> routes) async {
    await _persistRoutes(routes);
  }

  Future<bool> _persistRoutes(List<AiModelProxyRoute> routes) async {
    try {
      await context.read<AiModelProxyController>().saveRoutes(routes);
      return true;
    } catch (_) {
      if (mounted) {
        showOpenHandErrorSnack(
          context,
          AppLocalizations.of(context)!.settingsPersistenceSaveFailedBody,
        );
      }
      return false;
    }
  }

  Future<void> _addExposedModel(BuildContext context) async {
    final text = openHandTextResolver(context);
    final draft = await _showProxyNewExposedModelDialog(context);
    if (!context.mounted || draft == null) return;
    var modelId = draft.modelId.trim();
    var profile = const AiModelProfile();
    AiModelProxyBackend? importedBackend;
    if (draft.importExisting) {
      final settings = context.read<SettingsController>();
      final chosen = await showModelSearchSelector(
        context: context,
        models: settings.aiModels,
        recentSelections: settings.recentModelSelections,
      );
      if (!context.mounted || chosen == null) return;
      final provider = settings.aiModels
          .where(
            (item) =>
                item.id.trim().toLowerCase() == chosen.$1.trim().toLowerCase(),
          )
          .firstOrNull;
      if (provider == null) return;
      modelId = chosen.$2.trim();
      profile = provider.profileFor(modelId);
      if (modelId.isNotEmpty) {
        importedBackend = AiModelProxyBackend(
          providerId: provider.id.trim(),
          modelId: modelId,
        );
      }
    }
    if (modelId.isEmpty) return;
    final proxy = context.read<AiModelProxyController>();
    final routes = proxy.settings.routes;
    if (routes.any(
      (route) => _modelKey(route.exposedModel) == _modelKey(modelId),
    )) {
      showOpenHandErrorSnack(
        context,
        text(zh: '该暴露模型已存在。', en: 'That exposed model already exists.'),
      );
      return;
    }
    final newRoute = AiModelProxyRoute(
      exposedModel: modelId,
      profile: profile,
      backends: importedBackend == null
          ? const <AiModelProxyBackend>[]
          : <AiModelProxyBackend>[importedBackend],
    );
    final saved = await _persistRoutes([...routes, newRoute]);
    if (!saved) return;
    if (!mounted || !context.mounted) return;
    setState(() => _selectedModel = modelId);
    await _editExposedModel(context, newRoute);
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
    final routeKey = _modelKey(route.exposedModel);
    final routeIndex = currentRoutes.indexWhere(
      (item) => _modelKey(item.exposedModel) == routeKey,
    );
    if (routeIndex < 0) return;
    if (_modelKey(nextModelId) != routeKey &&
        currentRoutes.any(
          (item) => _modelKey(item.exposedModel) == _modelKey(nextModelId),
        )) {
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
    if (!await _persistRoutes(nextRoutes)) return;
    if (mounted && nextModelId != route.exposedModel) {
      setState(() => _selectedModel = nextModelId);
    }
  }

  Future<void> _editBackendModel(
    BuildContext context,
    String exposedModel,
    AiModelProxyBackend backend,
    int backendIndex,
  ) async {
    final settings = context.read<SettingsController>();
    final provider = settings.aiModels
        .where((item) => item.id == backend.providerId)
        .firstOrNull;
    if (provider == null) {
      showOpenHandErrorSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '后备模型提供商已不存在，无法编辑参数。',
          en: 'The backend provider no longer exists.',
        ),
      );
      return;
    }
    final result = await showAiModelProfileEditorDialog(
      context,
      modelId: backend.modelId,
      initialProfile:
          provider.modelProfiles[backend.modelId] ?? const AiModelProfile(),
      effectiveProfile: provider.profileFor(backend.modelId),
      protocolType: provider.protocolType,
      existingModelIds: provider.allModelIds,
    );
    if (!context.mounted || result == null) return;
    final nextModelId = result.modelId.trim();
    if (nextModelId.isEmpty) return;
    final modelProfiles = Map<String, AiModelProfile>.of(
      provider.modelProfiles,
    );
    if (nextModelId != backend.modelId) {
      modelProfiles.remove(backend.modelId);
    }
    modelProfiles[nextModelId] = result.profile;
    final saved = await settings.saveAiModel(
      provider.copyWith(
        modelProfiles: modelProfiles,
        availableModelIds: <String>[...provider.availableModelIds, nextModelId],
      ),
    );
    if (!context.mounted || !saved) {
      if (context.mounted && !saved) {
        showOpenHandErrorSnack(
          context,
          AppLocalizations.of(context)!.settingsPersistenceSaveFailedBody,
        );
      }
      return;
    }
    if (nextModelId != backend.modelId) {
      await _updateBackend(
        exposedModel,
        backendIndex,
        AiModelProxyBackend(
          providerId: backend.providerId,
          modelId: nextModelId,
          enabled: backend.enabled,
        ),
      );
    }
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
        .where(
          (item) =>
              _modelKey(item.exposedModel) != _modelKey(route.exposedModel),
        )
        .toList(growable: false);
    if (!await _persistRoutes(routes)) return;
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
        .where(
          (item) => _modelKey(item.exposedModel) == _modelKey(exposedModel),
        )
        .firstOrNull;
    final existing = {
      for (final backend
          in currentRoute?.backends ?? const <AiModelProxyBackend>[])
        '${backend.providerId.trim().toLowerCase()}\u0000${backend.modelId.trim().toLowerCase()}',
    };
    final chosen = await showModelSearchSelector(
      context: context,
      models: settings.aiModels,
      recentSelections: settings.recentModelSelections,
      modelFilter: (config, modelId) => !existing.contains(
        '${config.id.trim().toLowerCase()}\u0000${modelId.trim().toLowerCase()}',
      ),
    );
    if (!context.mounted || chosen == null) return;
    final current = proxy.settings.routes;
    final index = current.indexWhere(
      (item) => _modelKey(item.exposedModel) == _modelKey(exposedModel),
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
    await _persistRoutes(next);
  }

  Future<void> _updateBackend(
    String exposedModel,
    int backendIndex,
    AiModelProxyBackend backend,
  ) async {
    final proxy = context.read<AiModelProxyController>();
    final routeIndex = proxy.settings.routes.indexWhere(
      (item) => _modelKey(item.exposedModel) == _modelKey(exposedModel),
    );
    if (routeIndex < 0) return;
    final route = proxy.settings.routes[routeIndex];
    if (backendIndex < 0 || backendIndex >= route.backends.length) return;
    final backends = List<AiModelProxyBackend>.of(route.backends);
    backends[backendIndex] = backend;
    final routes = List<AiModelProxyRoute>.of(proxy.settings.routes);
    routes[routeIndex] = route.copyWith(backends: backends);
    await _persistRoutes(routes);
  }

  Future<void> _removeBackend(
    BuildContext context,
    String exposedModel,
    AiModelProxyBackend backend,
  ) async {
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: openHandLocalizedText(
        context,
        zh: '删除后备模型',
        en: 'Remove backend model',
      ),
      message: openHandLocalizedText(
        context,
        zh: '确认删除“${backend.modelId}”这个后备模型吗？',
        en: 'Remove backend model “${backend.modelId}”?',
      ),
      cancelLabel: openHandCancelLabel(context),
      confirmLabel: openHandLocalizedText(context, zh: '删除', en: 'Remove'),
      destructive: true,
    );
    if (!confirmed || !mounted || !context.mounted) return;
    final proxy = context.read<AiModelProxyController>();
    final routeIndex = proxy.settings.routes.indexWhere(
      (item) => _modelKey(item.exposedModel) == _modelKey(exposedModel),
    );
    if (routeIndex < 0) return;
    final route = proxy.settings.routes[routeIndex];
    final currentBackendIndex = route.backends.indexWhere(
      (item) => _backendKey(item) == _backendKey(backend),
    );
    if (currentBackendIndex < 0) return;
    final backends = List<AiModelProxyBackend>.of(route.backends)
      ..removeAt(currentBackendIndex);
    final routes = List<AiModelProxyRoute>.of(proxy.settings.routes);
    routes[routeIndex] = route.copyWith(backends: backends);
    await _persistRoutes(routes);
  }
}

class _ProxyNewExposedModelDraft {
  const _ProxyNewExposedModelDraft({required this.modelId})
    : importExisting = false;

  const _ProxyNewExposedModelDraft.import()
    : modelId = '',
      importExisting = true;

  final String modelId;
  final bool importExisting;
}

Future<_ProxyNewExposedModelDraft?> _showProxyNewExposedModelDialog(
  BuildContext context,
) async {
  final text = openHandTextResolver(context);
  final controller = TextEditingController();
  try {
    return await showAnimatedDialog<_ProxyNewExposedModelDraft>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          final canSubmit = controller.text.trim().isNotEmpty;
          return buildOpenHandAlertDialog(
            icon: const Icon(Icons.api_rounded),
            title: Text(text(zh: '新增暴露模型', en: 'Add exposed model')),
            content: SizedBox(
              width: 460,
              child: TextField(
                controller: controller,
                autofocus: true,
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() {}),
                onSubmitted: canSubmit
                    ? (_) => Navigator.of(dialogContext).pop(
                        _ProxyNewExposedModelDraft(
                          modelId: controller.text.trim(),
                        ),
                      )
                    : null,
                decoration: InputDecoration(
                  hintText: text(zh: '输入对外暴露的模型 ID', en: 'Exposed model ID'),
                ),
              ),
            ),
            actions: [
              OpenHandDialogActionButton.secondary(
                icon: Icons.file_download_outlined,
                label: text(zh: '从已有模型导入', en: 'Import existing model'),
                onPressed: () => Navigator.of(
                  dialogContext,
                ).pop(const _ProxyNewExposedModelDraft.import()),
              ),
              OpenHandDialogActionButton.secondary(
                label: openHandCancelLabel(context),
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
              OpenHandDialogActionButton.primary(
                icon: Icons.arrow_forward_rounded,
                label: text(zh: '下一步', en: 'Next'),
                onPressed: canSubmit
                    ? () => Navigator.of(dialogContext).pop(
                        _ProxyNewExposedModelDraft(
                          modelId: controller.text.trim(),
                        ),
                      )
                    : null,
              ),
            ],
          );
        },
      ),
    );
  } finally {
    controller.dispose();
  }
}

/// 模型映射图中的动态条目容器：保留已移除条目直到退场动画完成，避免列表
/// 数据变化时卡片瞬间消失；新增条目直接复用稳定布局，避免并行动画阻塞交互。
class _AnimatedMappingItems<T> extends StatefulWidget {
  const _AnimatedMappingItems({
    super.key,
    required this.items,
    required this.itemKey,
    required this.itemBuilder,
    required this.emptyChild,
    required this.gap,
    this.itemExtent,
    this.scrollController,
    this.scrollPadding = EdgeInsets.zero,
    this.scrollPhysics,
    this.onReorder,
    this.onDisplayItemsChanged,
    this.displayGroupKey,
  });

  final List<T> items;
  final String Function(T item) itemKey;
  final Widget Function(T item) itemBuilder;
  final Widget emptyChild;
  final double gap;
  final double? itemExtent;
  final ScrollController? scrollController;
  final EdgeInsets scrollPadding;
  final ScrollPhysics? scrollPhysics;
  final void Function(int oldIndex, int newIndex)? onReorder;
  final ValueChanged<int>? onDisplayItemsChanged;
  final String? displayGroupKey;

  @override
  State<_AnimatedMappingItems<T>> createState() =>
      _AnimatedMappingItemsState<T>();
}

class _AnimatedMappingItemsState<T> extends State<_AnimatedMappingItems<T>> {
  late List<T> _displayedItems;
  List<T>? _currentKeysSource;
  Set<String>? _currentKeys;
  int? _lastReportedDisplayCount;

  @override
  void initState() {
    super.initState();
    _displayedItems = List<T>.of(widget.items);
    _currentKeysSource = widget.items;
    _currentKeys = widget.items.map(widget.itemKey).toSet();
    _lastReportedDisplayCount = _displayedItems.length;
    // 弹窗自身已经负责进场动画，避免每个条目再创建一套并行动画。
  }

  @override
  void didUpdateWidget(covariant _AnimatedMappingItems<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.items, widget.items) &&
        oldWidget.displayGroupKey == widget.displayGroupKey) {
      return;
    }
    if (oldWidget.displayGroupKey != widget.displayGroupKey) {
      _displayedItems = List<T>.of(widget.items);
      _currentKeysSource = widget.items;
      _currentKeys = widget.items.map(widget.itemKey).toSet();
      return;
    }
    _currentKeysSource = widget.items;
    _currentKeys = widget.items.map(widget.itemKey).toSet();
    final currentKeys = _currentKeys!;
    final nextDisplayed = List<T>.of(widget.items);
    // 同数量更新通常是模型 ID 或配置项替换，新条目应原位接管，避免旧条目
    // 退场时与新条目叠成两行；数量减少时才保留旧条目播放退场动画。
    final preserveRemovedItems = oldWidget.items.length != widget.items.length;
    var hasRemovedItems = false;
    for (var index = 0; index < _displayedItems.length; index++) {
      final previous = _displayedItems[index];
      if (!currentKeys.contains(widget.itemKey(previous))) {
        if (!preserveRemovedItems) continue;
        hasRemovedItems = true;
        nextDisplayed.insert(index.clamp(0, nextDisplayed.length), previous);
      }
    }
    _displayedItems = nextDisplayed;
    if (hasRemovedItems) {
      _lastReportedDisplayCount = null;
      _scheduleDisplayCountNotification();
    }
  }

  void _scheduleDisplayCountNotification() {
    final callback = widget.onDisplayItemsChanged;
    if (callback == null ||
        _lastReportedDisplayCount == _displayedItems.length) {
      return;
    }
    final count = _displayedItems.length;
    _lastReportedDisplayCount = count;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.onDisplayItemsChanged == null) return;
      widget.onDisplayItemsChanged!(count);
    });
  }

  void _removeDismissed(String itemKey) {
    if (_keysFor(widget.items).contains(itemKey)) return;
    if (!mounted) return;
    setState(() {
      _displayedItems.removeWhere((item) => widget.itemKey(item) == itemKey);
    });
    _scheduleDisplayCountNotification();
  }

  @override
  Widget build(BuildContext context) {
    final motionSettings = openHandMotionSettingsOf(
      context,
      OpenHandMotionSettingsScope.dialog,
    );
    final itemMotionSettings = motionSettings.copyWith(
      entranceStyle: DialogAnimationStyle.none,
    );
    final currentKeys = _keysFor(widget.items);
    Widget buildItem(T item) {
      final itemId = widget.itemKey(item);
      return AnimatedAppearance(
        key: ValueKey<String>('proxy-mapping-item-$itemId'),
        settings: itemMotionSettings,
        present: currentKeys.contains(itemId),
        onDismissed: () => _removeDismissed(itemId),
        child: IgnorePointer(
          ignoring: !currentKeys.contains(itemId),
          child: RepaintBoundary(
            child: Padding(
              padding: EdgeInsets.only(bottom: widget.gap),
              child: widget.itemBuilder(item),
            ),
          ),
        ),
      );
    }

    final useLazyList =
        widget.scrollController != null &&
        widget.onReorder != null &&
        _displayedItems.isNotEmpty;
    if (useLazyList) {
      return ReorderableListView.builder(
        scrollController: widget.scrollController,
        primary: false,
        padding: widget.scrollPadding,
        physics: widget.scrollPhysics,
        itemExtent: widget.itemExtent,
        buildDefaultDragHandles: false,
        proxyDecorator: (child, index, animation) =>
            buildOpenHandReorderProxy(context, child, animation),
        itemCount: _displayedItems.length,
        onReorder: widget.onReorder!,
        itemBuilder: (context, index) {
          final item = _displayedItems[index];
          final itemId = widget.itemKey(item);
          return KeyedSubtree(
            key: ValueKey<String>('proxy-reorder-item-$itemId'),
            child: ReorderableDelayedDragStartListener(
              index: index,
              child: buildItem(item),
            ),
          );
        },
      );
    }

    final items = _displayedItems.isEmpty
        ? const <Widget>[]
        : widget.onReorder == null
        ? <Widget>[for (final item in _displayedItems) buildItem(item)]
        : <Widget>[
            ReorderableListView.builder(
              primary: false,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemExtent: widget.itemExtent,
              buildDefaultDragHandles: false,
              proxyDecorator: (child, index, animation) =>
                  buildOpenHandReorderProxy(context, child, animation),
              itemCount: _displayedItems.length,
              onReorder: widget.onReorder!,
              itemBuilder: (context, index) {
                final item = _displayedItems[index];
                final itemId = widget.itemKey(item);
                return KeyedSubtree(
                  key: ValueKey<String>('proxy-reorder-item-$itemId'),
                  child: ReorderableDelayedDragStartListener(
                    index: index,
                    child: buildItem(item),
                  ),
                );
              },
            ),
          ];
    // 退场动画期间保留旧条目，等其完全移除后再挂载空状态，避免两者叠加撑高布局。
    final showEmptyChild = widget.items.isEmpty && _displayedItems.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...items,
        if (showEmptyChild)
          AnimatedAppearance(
            key: const ValueKey<String>('proxy-mapping-empty-item'),
            settings: itemMotionSettings,
            child: widget.emptyChild,
          ),
      ],
    );
  }

  Set<String> _keysFor(List<T> items) {
    if (identical(_currentKeysSource, items) && _currentKeys != null) {
      return _currentKeys!;
    }
    _currentKeysSource = items;
    return _currentKeys = items.map(widget.itemKey).toSet();
  }
}

class _MindMapConnector extends StatelessWidget {
  const _MindMapConnector({
    required this.height,
    required this.sourceY,
    required this.branchCount,
    required this.branchTop,
    this.branchCenterY,
    required this.branchHeight,
    required this.gap,
    required this.color,
  });

  final double height;
  final double sourceY;
  final int branchCount;
  final double branchTop;
  final double? branchCenterY;
  final double branchHeight;
  final double gap;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: _ProxyModelsDialogState._connectorWidth,
    height: height,
    child: CustomPaint(
      painter: _MindMapConnectorPainter(
        sourceY: sourceY,
        branchCount: branchCount,
        branchTop: branchTop,
        branchCenterY: branchCenterY,
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
    this.branchCenterY,
    required this.branchHeight,
    required this.gap,
    required this.color,
  });

  final double sourceY;
  final int branchCount;
  final double branchTop;
  final double? branchCenterY;
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
      final branchCenter = (branchCenterY ?? source)
          .clamp(0.0, size.height)
          .toDouble();
      canvas.drawLine(
        Offset(spineX, source),
        Offset(spineX, branchCenter),
        paint,
      );
      canvas.drawLine(
        Offset(spineX, branchCenter),
        Offset(size.width, branchCenter),
        paint,
      );
      return;
    }
    final firstCenter = branchTop + branchHeight / 2;
    final lastCenter = firstCenter + (branchCount - 1) * (branchHeight + gap);
    final first = firstCenter.clamp(0.0, size.height).toDouble();
    final last = lastCenter.clamp(0.0, size.height).toDouble();
    canvas.drawLine(Offset(spineX, source), Offset(spineX, first), paint);
    canvas.drawLine(Offset(spineX, first), Offset(spineX, last), paint);
    for (var index = 0; index < branchCount; index++) {
      final y = (firstCenter + index * (branchHeight + gap))
          .clamp(0.0, size.height)
          .toDouble();
      canvas.drawLine(Offset(spineX, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_MindMapConnectorPainter oldDelegate) =>
      oldDelegate.sourceY != sourceY ||
      oldDelegate.branchCount != branchCount ||
      oldDelegate.branchTop != branchTop ||
      oldDelegate.branchCenterY != branchCenterY ||
      oldDelegate.branchHeight != branchHeight ||
      oldDelegate.gap != gap ||
      oldDelegate.color != color;
}

class _ProxyMappingCard extends StatelessWidget {
  const _ProxyMappingCard({
    required this.title,
    required this.subtitle,
    required this.enabled,
    this.selected = false,
    this.onTap,
    this.onToggle,
    this.onEdit,
    this.onRemove,
  });

  final String title;
  final String subtitle;
  final bool enabled;
  final bool selected;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onToggle;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final borderRadius = BorderRadius.circular(kOpenHandRadius16);
    final card = AnimatedContainer(
      duration: openHandMotionDuration(context, kOpenHandMotion180),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 8, 10),
      decoration: BoxDecoration(
        color: enabled
            ? selected
                  ? colors.primaryContainer
                  : colors.surfaceContainerHighest
            : colors.surfaceContainerLow,
        borderRadius: borderRadius,
        border: Border.all(
          color: selected
              ? colors.primary
              : enabled
              ? colors.outlineVariant
              : colors.outlineVariant.withValues(alpha: 0.72),
          width: selected ? 1.6 : 1,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: enabled ? null : colors.onSurfaceVariant,
                    ),
                  ),
                  kOpenHandGap4,
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Switch(value: enabled, onChanged: onToggle),
          const SizedBox(width: 4),
          ServiceDialogCompactIconButton(
            tooltip: openHandLocalizedText(
              context,
              zh: '编辑模型参数',
              en: 'Edit model parameters',
            ),
            foregroundColor: colors.primary,
            icon: const Icon(Icons.tune_rounded, size: 20),
            onPressed: onEdit,
          ),
          const SizedBox(width: 4),
          ServiceDialogCompactIconButton(
            tooltip: openHandLocalizedText(
              context,
              zh: '删除模型',
              en: 'Delete model',
            ),
            foregroundColor: colors.error,
            icon: const Icon(Icons.delete_outline_rounded, size: 20),
            onPressed: onRemove,
          ),
        ],
      ),
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, borderRadius: borderRadius, child: card),
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

class _ProxySettingsDialog extends StatefulWidget {
  const _ProxySettingsDialog();
  @override
  State<_ProxySettingsDialog> createState() => _ProxySettingsDialogState();
}

class _ProxySettingsDialogState extends State<_ProxySettingsDialog> {
  late final TextEditingController _listenHost;
  late bool _auth;
  late AiModelProxyApiStyle _style;
  late AiModelProxyLimitScope _limitScope;
  late AiModelProxyLimitMode _limitMode;
  late AiModelProxyRetryPolicy _retry;
  late AiModelProxySchedulingStrategy _scheduling;
  late int _threshold;
  late int _retryCount;
  late int _listenPort;
  late TextEditingController _key;
  bool _showApiKey = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final value = context.read<AiModelProxyController>().settings;
    _listenHost = TextEditingController(text: value.listenHost);
    _listenPort = value.listenPort;
    _auth = value.requireAuthentication;
    _style = value.apiStyle;
    _limitScope = value.limitScope;
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
    if (_saving) return;
    final text = openHandTextResolver(context);
    final host = _listenHost.text.trim().isEmpty
        ? aiModelProxyDefaultListenHost
        : _listenHost.text.trim();
    final apiKey = _key.text.trim();
    if (_auth && apiKey.isEmpty) {
      showOpenHandErrorSnack(
        context,
        text(
          zh: '启用 API 鉴权后必须填写 API Key。',
          en: 'Enter an API key when authentication is enabled.',
        ),
      );
      return;
    }
    if (!_auth && !AiModelProxyController.isLoopbackListenHost(host)) {
      showOpenHandErrorSnack(
        context,
        text(
          zh: '监听非本机回环地址时必须启用 API 鉴权。',
          en: 'Authentication is required for non-loopback listeners.',
        ),
      );
      return;
    }
    final controller = context.read<AiModelProxyController>();
    setState(() => _saving = true);
    try {
      await controller.saveSettings(
        controller.settings.copyWith(
          listenHost: host,
          listenPort: _listenPort,
          requireAuthentication: _auth,
          apiKey: apiKey,
          apiStyle: _style,
          limitScope: _limitScope,
          limitMode: _limitMode,
          limitThreshold: _threshold,
          retryPolicy: _retry,
          retryCount: _retryCount,
          scheduling: _scheduling,
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showOpenHandErrorSnack(
        context,
        text(
          zh: '保存中转站设置失败，请重试。',
          en: 'Failed to save proxy settings. Try again.',
        ),
      );
    }
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
                        zh: '默认 $aiModelProxyDefaultListenHost；非回环地址必须启用鉴权。',
                        en: 'Default $aiModelProxyDefaultListenHost; remote listeners require authentication.',
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
                    onChanged: (value) => setState(() {
                      _auth = value;
                      if (!value) _showApiKey = false;
                    }),
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
                      obscureText: !_showApiKey,
                      autocorrect: false,
                      enableSuggestions: false,
                      keyboardType: TextInputType.visiblePassword,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        labelText: text(zh: 'API Key', en: 'API key'),
                        suffixIcon: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: ServiceDialogCompactIconButton(
                            size: 32,
                            tooltip: _showApiKey
                                ? text(zh: '隐藏 API Key', en: 'Hide API key')
                                : text(zh: '显示 API Key', en: 'Show API key'),
                            onPressed: () =>
                                setState(() => _showApiKey = !_showApiKey),
                            icon: Icon(
                              _showApiKey
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              size: 18,
                            ),
                          ),
                        ),
                        suffixIconConstraints: const BoxConstraints.tightFor(
                          width: 48,
                          height: 40,
                        ),
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
                  _DropdownField<AiModelProxyLimitScope>(
                    label: text(zh: '限流范围', en: 'Rate limit scope'),
                    value: _limitScope,
                    values: AiModelProxyLimitScope.values,
                    labelOf: (item) => aiModelProxyLimitScopeLabel(item, text),
                    onChanged: (value) => setState(() => _limitScope = value),
                  ),
                  kOpenHandGap12,
                  _DropdownField<AiModelProxyLimitMode>(
                    label: text(zh: '限流方式', en: 'Rate limit mode'),
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
                    labelOf: (item) => aiModelProxyRetryPolicyLabel(item, text),
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
                      labelOf: (item) =>
                          aiModelProxySchedulingLabel(item, text),
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
                  busy: _saving,
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
  Widget build(BuildContext context) => AnimatedDropdownButtonFormField<T>(
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
    final text = openHandTextResolver(context);
    final mode = record.proxyMode.trim();
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
          '${aiModelProxyApiStyleLabel(record.apiStyle, text)} · ${record.tokens} tokens · ${record.durationMs} ms'
          '${mode.isEmpty ? '' : ' · ${aiModelProxyDispatchModeLabel(mode, text)}'}'
          '${record.proxyEndpoint.isEmpty ? '' : ' · ${record.proxyEndpoint}'}'
          '${record.clientEndpoint.isEmpty ? '' : ' · ${record.clientEndpoint}'}'
          '${record.error == null ? '' : ' · ${record.error}'}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Text(record.startedAt.toLocal().toString().substring(0, 16)),
      ),
    );
  }
}

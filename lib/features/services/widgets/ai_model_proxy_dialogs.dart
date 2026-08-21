import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/state/settings_controller.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../../../shared/util/localized_text.dart';
import '../../ai/index.dart';
import '../../settings/index.dart' show showAiModelEditorDialog;
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
                  onPressed: () async {
                    await showAiModelProxyModelsDialog(context);
                  },
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
                        await settings.moveAiModel(oldIndex, target);
                      },
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
                          onDelete: () => settings.deleteAiModel(model.id),
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
    final colors = Theme.of(context).colorScheme;
    final text = openHandTextResolver(context);
    final modelCount = model.allModelIds.length;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: colors.secondaryContainer,
          foregroundColor: colors.onSecondaryContainer,
          child: Text('${index + 1}'),
        ),
        title: Text(model.providerLabel),
        subtitle: Text(
          '${model.apiDialect.storageValue} · ${text(zh: '模型 $modelCount 个', en: '$modelCount models')}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Wrap(
          spacing: 4,
          children: [
            IconButton(
              tooltip: text(zh: '编辑', en: 'Edit'),
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: text(zh: '删除', en: 'Delete'),
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
            ReorderableDragStartListener(
              index: index,
              child: IconButton(
                tooltip: text(zh: '拖动排序', en: 'Reorder'),
                onPressed: () {},
                icon: const Icon(Icons.drag_indicator_rounded),
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
    final route = routes
        .where((item) => item.exposedModel == selected)
        .firstOrNull;
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
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Expanded(
                    child: _MindMapNode(
                      title: 'OpenHand',
                      icon: Icons.apps_rounded,
                      primary: true,
                    ),
                  ),
                  const _MindMapConnector(),
                  SizedBox(
                    width: 220,
                    child: ListView(
                      children: [
                        for (final model in exposedModels)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _MindMapNode(
                              title: model,
                              icon: Icons.api_rounded,
                              selected: model == selected,
                              onTap: () =>
                                  setState(() => _selectedModel = model),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const _MindMapConnector(),
                  Expanded(
                    flex: 2,
                    child: route == null
                        ? Center(
                            child: Text(
                              text(
                                zh: '选择一个暴露模型查看后备模型。',
                                en: 'Select an exposed model.',
                              ),
                            ),
                          )
                        : ListView(
                            children: [
                              if (route.backends.isEmpty)
                                _EmptyBackendCard(
                                  text: text(zh: '暂无后备模型', en: 'No backends'),
                                ),
                              for (final backend in route.backends)
                                _BackendTile(
                                  backend: backend,
                                  settings: settings,
                                ),
                              const SizedBox(height: 8),
                              FilledButton.tonalIcon(
                                onPressed: () =>
                                    _addBackend(context, selected!),
                                icon: const Icon(Icons.add_rounded),
                                label: Text(
                                  text(zh: '添加后备模型', en: 'Add backend'),
                                ),
                              ),
                            ],
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

  Future<void> _addBackend(BuildContext context, String exposedModel) async {
    final settings = context.read<SettingsController>();
    final proxy = context.read<AiModelProxyController>();
    final candidates =
        <({String providerId, String providerName, String modelId})>[
          for (final provider in settings.aiModels)
            for (final modelId in provider.allModelIds)
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
}

class _MindMapConnector extends StatelessWidget {
  const _MindMapConnector();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 34,
    child: Center(
      child: Container(
        height: 2,
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
    ),
  );
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
            ? colors.secondaryContainer
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
  Widget build(BuildContext context) => Card(
    child: Padding(padding: const EdgeInsets.all(18), child: Text(text)),
  );
}

class _BackendTile extends StatelessWidget {
  const _BackendTile({required this.backend, required this.settings});
  final AiModelProxyBackend backend;
  final SettingsController settings;
  @override
  Widget build(BuildContext context) {
    final provider = settings.aiModels
        .where((item) => item.id == backend.providerId)
        .firstOrNull;
    return Card(
      child: ListTile(
        leading: Icon(
          backend.enabled
              ? Icons.check_circle_outline_rounded
              : Icons.pause_circle_outline_rounded,
        ),
        title: Text(backend.modelId),
        subtitle: Text(provider?.displayName ?? backend.providerId),
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
                for (final item in candidates)
                  ListTile(
                    leading: const Icon(Icons.cloud_outlined),
                    title: Text(item.modelId),
                    subtitle: Text(item.providerName),
                    onTap: () => Navigator.of(
                      context,
                    ).pop((providerId: item.providerId, modelId: item.modelId)),
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
              title: text(zh: '中转站服务设置', en: 'Proxy service settings'),
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
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _auth,
                    onChanged: (value) => setState(() => _auth = value),
                    title: Text(text(zh: 'API 鉴权', en: 'API authentication')),
                    subtitle: Text(
                      text(
                        zh: '启用后请求必须携带与 API 风格一致的 Key。',
                        en: 'Require a matching API key on incoming requests.',
                      ),
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
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OpenHandDialogActionButton.secondary(
                  label: text(zh: '取消', en: 'Cancel'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                kOpenHandHGap10,
                FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(text(zh: '保存设置', en: 'Save settings')),
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

class _NumberStepper extends StatelessWidget {
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
  Widget build(BuildContext context) => InputDecorator(
    decoration: InputDecoration(labelText: label),
    child: Row(
      children: [
        IconButton(
          onPressed: value <= min ? null : () => onChanged(value - 1),
          icon: const Icon(Icons.remove_rounded),
        ),
        Expanded(
          child: Center(
            child: Text(
              '$value',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),
        IconButton(
          onPressed: value >= max ? null : () => onChanged(value + 1),
          icon: const Icon(Icons.add_rounded),
        ),
      ],
    ),
  );
}

class _ProxyUsageDialog extends StatefulWidget {
  const _ProxyUsageDialog();
  @override
  State<_ProxyUsageDialog> createState() => _ProxyUsageDialogState();
}

class _ProxyUsageDialogState extends State<_ProxyUsageDialog> {
  AiUsageSnapshot? _snapshot;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final snapshot = await AiUsageTracker.instance.loadSnapshot(
        const AiUsageFilter(),
      );
      if (mounted) {
        setState(() {
          _snapshot = snapshot;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = openHandTextResolver(context);
    final proxy = context.watch<AiModelProxyController>();
    final stats = proxy.settings;
    final snapshot = _snapshot;
    final records = stats.recentRequests;
    return ServiceDialogInteractionTheme(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
        child: Column(
          children: [
            _ProxyDialogHeader(
              title: text(zh: '中转站使用统计', en: 'Proxy usage analytics'),
              subtitle: text(
                zh: '汇总请求、成功率、Token、成本与耗时，保留全局追踪的详细记录。',
                en: 'Requests, success rate, tokens, cost and latency with global traces.',
              ),
              icon: Icons.query_stats_rounded,
              onClose: () => Navigator.of(context).pop(),
            ),
            kOpenHandGap16,
            if (_loading) const LinearProgressIndicator(minHeight: 3),
            kOpenHandGap14,
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _Metric(
                  label: text(zh: '请求', en: 'Requests'),
                  value: '${stats.requestCount}',
                ),
                _Metric(
                  label: text(zh: '成功率', en: 'Success rate'),
                  value: '${(stats.successRate * 100).toStringAsFixed(1)}%',
                ),
                _Metric(
                  label: text(zh: 'Token', en: 'Tokens'),
                  value: '${stats.totalTokens}',
                ),
                _Metric(
                  label: text(zh: '平均耗时', en: 'Avg latency'),
                  value: '${stats.averageDurationMs.toStringAsFixed(0)} ms',
                ),
              ],
            ),
            kOpenHandGap16,
            Expanded(
              child: records.isNotEmpty
                  ? ListView.separated(
                      itemCount: records.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) => _ProxyRecordTile(
                        record: records.reversed.elementAt(index),
                      ),
                    )
                  : snapshot == null
                  ? Center(
                      child: Text(
                        text(
                          zh: '暂无全局请求追踪记录。',
                          en: 'No global request traces yet.',
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: snapshot.recentRequests.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) => _UsageRecordTile(
                        record: snapshot.recentRequests[index],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.titleLarge),
        ],
      ),
    ),
  );
}

class _UsageRecordTile extends StatelessWidget {
  const _UsageRecordTile({required this.record});
  final AiUsageRequestRecord record;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: Icon(
        record.status == AiUsageRequestStatus.success
            ? Icons.check_circle_outline_rounded
            : Icons.error_outline_rounded,
      ),
      title: Text('${record.providerName} / ${record.modelId}'),
      subtitle: Text(
        '${record.apiFamily} · ${record.usage.totalTokens} tokens · ${record.durationMs} ms',
      ),
      trailing: Text(record.startedAt.toLocal().toString().substring(0, 16)),
    ),
  );
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
          '${record.apiStyle} · ${record.tokens} tokens · ${record.durationMs} ms${record.error == null ? '' : ' · ${record.error}'}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Text(record.startedAt.toLocal().toString().substring(0, 16)),
      ),
    );
  }
}

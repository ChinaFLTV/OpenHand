part of 'settings_view.dart';

const double _offlineSpeechPanelMaxHeight = 760;

class _OfflineSpeechModelPanel extends StatefulWidget {
  const _OfflineSpeechModelPanel({
    required this.kind,
    required this.settings,
    required this.onChanged,
    this.textPolishingSettings,
    this.availableModels = const <AiModelConfig>[],
    this.recentModelSelections = const <RecentModelSelection>[],
    this.onTextPolishingChanged,
  });

  final OfflineSpeechKind kind;
  final OfflineSpeechModelSettings settings;
  final Future<bool> Function(OfflineSpeechModelSettings settings) onChanged;
  final OfflineSpeechTextPolishingSettings? textPolishingSettings;
  final List<AiModelConfig> availableModels;
  final List<RecentModelSelection> recentModelSelections;
  final Future<bool> Function(OfflineSpeechTextPolishingSettings settings)?
  onTextPolishingChanged;

  @override
  State<_OfflineSpeechModelPanel> createState() =>
      _OfflineSpeechModelPanelState();
}

class _OfflineSpeechModelPanelState extends State<_OfflineSpeechModelPanel> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final models = OfflineSpeechModelCatalog.forKind(widget.kind);
    return AnimatedBuilder(
      animation: OfflineSpeechModelService.instance,
      builder: (context, _) => ConstrainedBox(
        constraints: const BoxConstraints(
          maxHeight: _offlineSpeechPanelMaxHeight,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _OfflineSpeechPanelHeader(
              kind: widget.kind,
              modelCount: models.length,
            ),
            if (widget.kind == OfflineSpeechKind.recognition &&
                widget.textPolishingSettings != null &&
                widget.onTextPolishingChanged != null) ...<Widget>[
              kOpenHandGap18,
              _OfflineSpeechTextPolishingControls(
                settings: widget.textPolishingSettings!,
                availableModels: widget.availableModels,
                recentModelSelections: widget.recentModelSelections,
                onChanged: widget.onTextPolishingChanged!,
              ),
            ],
            kOpenHandGap10,
            Flexible(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLowest.withValues(
                    alpha: 0.72,
                  ),
                  borderRadius: kOpenHandBorderRadius16,
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.52,
                    ),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: OpenHandSafeScrollbar(
                    controller: _scrollController,
                    child: ListView.separated(
                      controller: _scrollController,
                      primary: false,
                      shrinkWrap: true,
                      padding: const EdgeInsets.only(right: 4),
                      itemCount: models.length,
                      separatorBuilder: (_, _) => kOpenHandGap12,
                      itemBuilder: (context, index) => _OfflineSpeechModelCard(
                        key: ValueKey<String>(
                          'offlineSpeechModel-${models[index].id}',
                        ),
                        model: models[index],
                        settings: widget.settings,
                        onChanged: widget.onChanged,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfflineSpeechTextPolishingControls extends StatefulWidget {
  const _OfflineSpeechTextPolishingControls({
    required this.settings,
    required this.availableModels,
    required this.recentModelSelections,
    required this.onChanged,
  });

  final OfflineSpeechTextPolishingSettings settings;
  final List<AiModelConfig> availableModels;
  final List<RecentModelSelection> recentModelSelections;
  final Future<bool> Function(OfflineSpeechTextPolishingSettings settings)
  onChanged;

  @override
  State<_OfflineSpeechTextPolishingControls> createState() =>
      _OfflineSpeechTextPolishingControlsState();
}

class _OfflineSpeechTextPolishingControlsState
    extends State<_OfflineSpeechTextPolishingControls> {
  bool _modelSelectorOpen = false;
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    _enabled = widget.settings.enabled;
  }

  @override
  void didUpdateWidget(
    covariant _OfflineSpeechTextPolishingControls oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings.enabled != widget.settings.enabled) {
      _enabled = widget.settings.enabled;
    }
  }

  AiModelConfig? _selectedModel() {
    final configId = widget.settings.modelConfigId;
    final modelId = widget.settings.modelId;
    if (configId == null || modelId == null) return null;
    final provider = widget.availableModels
        .where(
          (candidate) =>
              candidate.id == configId &&
              candidate.allModelIds.contains(modelId),
        )
        .firstOrNull;
    return provider?.copyWith(modelId: modelId);
  }

  List<AiReasoningEffortOption> _reasoningOptions(AiModelConfig? model) {
    if (model == null || !model.resolvedReasoningEffortControlEnabled) {
      return const <AiReasoningEffortOption>[];
    }
    return model.resolvedReasoningEffortOptions
        .where((option) => option.isSelectable)
        .toList(growable: false);
  }

  String? _normalizedReasoningEffort(AiModelConfig? model, String? configured) {
    final options = _reasoningOptions(model);
    if (options.isEmpty) return null;
    if (options.length == 1) return options.single.value;
    final normalized = configured?.trim();
    if (normalized != null &&
        options.any((option) => option.value == normalized)) {
      return normalized;
    }
    final modelDefault = model?.resolvedReasoningEffort;
    if (modelDefault != null &&
        options.any((option) => option.value == modelDefault)) {
      return modelDefault;
    }
    return options.first.value;
  }

  Future<void> _save(OfflineSpeechTextPolishingSettings next) async {
    if (await widget.onChanged(next) || !mounted) return;
    _showOfflineSpeechPersistenceFailure(context);
  }

  Future<void> _setEnabled(bool value) async {
    if (_enabled == value) return;
    setState(() => _enabled = value);
    final saved = await widget.onChanged(widget.settings.setEnabled(value));
    if (!mounted || saved) return;
    setState(() => _enabled = widget.settings.enabled);
    _showOfflineSpeechPersistenceFailure(context);
  }

  Future<void> _selectModel() async {
    if (_modelSelectorOpen || widget.availableModels.isEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _modelSelectorOpen = true);
    final picked = await showModelSearchSelector(
      context: context,
      models: widget.availableModels,
      recentSelections: widget.recentModelSelections,
      selectedConfigId: widget.settings.modelConfigId,
      selectedModelId: widget.settings.modelId,
    );
    if (!mounted) return;
    setState(() => _modelSelectorOpen = false);
    if (picked == null) return;
    final provider = widget.availableModels
        .where((candidate) => candidate.id == picked.$1)
        .firstOrNull;
    final model = provider?.copyWith(modelId: picked.$2);
    final next = widget.settings.selectModel(
      modelConfigId: picked.$1,
      modelId: picked.$2,
      reasoningEffort: _normalizedReasoningEffort(model, null),
    );
    await context.read<SettingsController>().addRecentModelSelection(
      picked.$1,
      picked.$2,
    );
    if (!mounted) return;
    await _save(next);
  }

  Future<void> _selectReasoningEffort(BuildContext anchorContext) async {
    final model = _selectedModel();
    final options = _reasoningOptions(model);
    if (options.length <= 1) return;
    final currentValue = _normalizedReasoningEffort(
      model,
      widget.settings.reasoningEffort,
    );
    await showReasoningEffortSelector(
      context: context,
      anchorContext: anchorContext,
      options: options,
      currentValue: currentValue,
      onChanged: (effort) async {
        final saved = await widget.onChanged(
          widget.settings.setReasoningEffort(effort),
        );
        if (!mounted || saved) return saved;
        _showOfflineSpeechPersistenceFailure(context);
        return false;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedModel = _selectedModel();
    final options = _reasoningOptions(selectedModel);
    final reasoningEffort = _normalizedReasoningEffort(
      selectedModel,
      widget.settings.reasoningEffort,
    );
    final localeName = Localizations.localeOf(context).toLanguageTag();
    final reasoningLabel = reasoningEffort == null
        ? openHandLocalizedText(context, zh: '关闭', en: 'Off')
        : options
                  .where((option) => option.value == reasoningEffort)
                  .firstOrNull
                  ?.labelForLocaleName(localeName) ??
              reasoningEffort;
    final hasModels = widget.availableModels.any(
      (model) => model.allModelIds.isNotEmpty,
    );
    final modelLabel = selectedModel == null
        ? openHandLocalizedText(
            context,
            zh: hasModels ? '选择润色模型' : '暂无可用模型',
            en: hasModels ? 'Choose polishing model' : 'No models available',
          )
        : '${selectedModel.providerLabel} · ${selectedModel.displayName}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _ResponsiveSettingRow(
          title: openHandLocalizedText(
            context,
            zh: '启用文本润色',
            en: 'Enable Text Polishing',
          ),
          subtitle: openHandLocalizedText(
            context,
            zh: '识别完成后使用所选模型修正错字、标点和断句。默认关闭。',
            en: 'Use the selected model to correct words, punctuation, and sentence breaks after recognition. Off by default.',
          ),
          control: Align(
            alignment: AlignmentDirectional.centerStart,
            child: _SettingsSwitch(value: _enabled, onChanged: _setEnabled),
          ),
        ),
        _AnimatedSettingReveal(
          visible: _enabled,
          child: Padding(
            padding: const EdgeInsets.only(top: 16),
            child: _ResponsiveSettingRow(
              title: openHandLocalizedText(
                context,
                zh: '润色模型',
                en: 'Polishing Model',
              ),
              subtitle: openHandLocalizedText(
                context,
                zh: '选择语音识别完成后用于整理文本的 AI 模型。',
                en: 'Choose the AI model used to refine recognized text.',
              ),
              control: _OfflineSpeechSelectorButton(
                label: modelLabel,
                enabled: hasModels,
                expanded: _modelSelectorOpen,
                onPressed: _selectModel,
              ),
            ),
          ),
        ),
        _AnimatedSettingReveal(
          visible: _enabled,
          child: Padding(
            padding: const EdgeInsets.only(top: 16),
            child: _ResponsiveSettingRow(
              title: openHandLocalizedText(
                context,
                zh: '润色模型推理强度',
                en: 'Polishing Reasoning Effort',
              ),
              subtitle: options.length > 1
                  ? openHandLocalizedText(
                      context,
                      zh: '控制润色模型处理识别文本时的推理投入。',
                      en: 'Control how much reasoning the model uses when refining recognized text.',
                    )
                  : openHandLocalizedText(
                      context,
                      zh: options.length == 1
                          ? '当前模型仅支持一种推理强度，已自动固定。'
                          : '当前模型不支持可配置的推理强度。',
                      en: options.length == 1
                          ? 'This model supports one fixed reasoning effort.'
                          : 'This model does not support configurable reasoning effort.',
                    ),
              control: Builder(
                builder: (anchorContext) => _OfflineSpeechSelectorButton(
                  label: reasoningLabel,
                  enabled: options.length > 1,
                  onPressed: () => _selectReasoningEffort(anchorContext),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _OfflineSpeechSelectorButton extends StatelessWidget {
  const _OfflineSpeechSelectorButton({
    required this.label,
    required this.enabled,
    required this.onPressed,
    this.expanded = false,
  });

  final String label;
  final bool enabled;
  final VoidCallback onPressed;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final disabledColor = colorScheme.onSurfaceVariant.withValues(alpha: 0.46);
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: enabled ? onPressed : null,
        style:
            OutlinedButton.styleFrom(
              alignment: AlignmentDirectional.centerStart,
              foregroundColor: colorScheme.onSurface,
              disabledForegroundColor: disabledColor,
              disabledBackgroundColor: colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.62),
              minimumSize: const Size(0, 48),
              padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 10, 10),
              animationDuration: openHandMotionDuration(
                context,
                kOpenHandMotion200,
              ),
              shape: const RoundedRectangleBorder(
                borderRadius: kOpenHandBorderRadius14,
              ),
            ).copyWith(
              side: WidgetStateProperty.resolveWith<BorderSide>((states) {
                final disabled = states.contains(WidgetState.disabled);
                return BorderSide(
                  color: colorScheme.outlineVariant.withValues(
                    alpha: disabled ? 0.38 : 0.8,
                  ),
                );
              }),
              mouseCursor: WidgetStateProperty.resolveWith<MouseCursor>(
                (states) => states.contains(WidgetState.disabled)
                    ? SystemMouseCursors.forbidden
                    : SystemMouseCursors.click,
              ),
            ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: enabled ? colorScheme.onSurface : disabledColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            kOpenHandHGap8,
            AnimatedSwitcher(
              duration: openHandMotionDuration(context, kOpenHandMotion200),
              switchInCurve: kOpenHandSwitchInCurve,
              switchOutCurve: kOpenHandSwitchOutCurve,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(scale: animation, child: child),
              ),
              child: enabled
                  ? AnimatedRotation(
                      key: const ValueKey<bool>(true),
                      turns: expanded ? 0.5 : 0,
                      duration: openHandMotionDuration(
                        context,
                        kOpenHandMotion200,
                      ),
                      curve: kOpenHandEmphasizedCurve,
                      child: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 20,
                      ),
                    )
                  : const Icon(
                      Icons.lock_outline_rounded,
                      key: ValueKey<bool>(false),
                      size: 18,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfflineSpeechPanelHeader extends StatelessWidget {
  const _OfflineSpeechPanelHeader({
    required this.kind,
    required this.modelCount,
  });

  final OfflineSpeechKind kind;
  final int modelCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRecognition = kind == OfflineSpeechKind.recognition;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Text(
              isRecognition ? '语音识别' : '语音朗读',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            _OfflineSpeechBadge(
              label: '$modelCount 个本地模型',
              color: theme.colorScheme.primary,
            ),
            const _OfflineSpeechBadge(
              label: '完全离线',
              color: OpenHandStatusColors.success,
            ),
          ],
        ),
        kOpenHandGap5,
        Text(
          isRecognition
              ? '下载并管理本地 ASR／STT 模型。全程离线，当前仅可启用一个识别模型。'
              : '下载并管理本地 TTS 模型。全程离线，当前仅可启用一个朗读模型。',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
        kOpenHandGap5,
        _OfflineSpeechHardwareSummary(
          profile: OfflineSpeechModelService.instance.hardwareProfile,
        ),
      ],
    );
  }
}

class _OfflineSpeechModelCard extends StatefulWidget {
  const _OfflineSpeechModelCard({
    super.key,
    required this.model,
    required this.settings,
    required this.onChanged,
  });

  final OfflineSpeechModelDefinition model;
  final OfflineSpeechModelSettings settings;
  final Future<bool> Function(OfflineSpeechModelSettings settings) onChanged;

  @override
  State<_OfflineSpeechModelCard> createState() =>
      _OfflineSpeechModelCardState();
}

class _OfflineSpeechModelCardState extends State<_OfflineSpeechModelCard> {
  bool _expanded = false;
  bool _testing = false;
  bool _mutating = false;
  Map<String, Object?>? _draftConfiguration;

  Map<String, Object?> get _configuration =>
      _draftConfiguration ?? widget.settings.configuration(widget.model);

  bool get _enabled => widget.settings.enabledModelId == widget.model.id;

  @override
  void didUpdateWidget(covariant _OfflineSpeechModelCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.model.id != widget.model.id) {
      _draftConfiguration = null;
      _expanded = false;
    }
    if (!_enabled && oldWidget.settings.enabledModelId == widget.model.id) {
      _expanded = false;
    }
    final persisted = widget.settings.configuration(widget.model);
    if (_draftConfiguration != null &&
        _settingsJsonEquals(_draftConfiguration, persisted)) {
      _draftConfiguration = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final service = OfflineSpeechModelService.instance;
    final state = service.stateOf(widget.model);
    final installed = service.isInstalled(widget.model);
    final availability = service.availabilityFor(widget.model, _configuration);
    final hardwareAvailable = availability.available;
    final requiresUpdate =
        installed &&
        service.requiresDownloadForConfiguration(widget.model, _configuration);
    final requiresModelFiles = service.requiresModelFilesForConfiguration(
      widget.model,
      _configuration,
    );
    final requiresRuntime = service.requiresRuntimePreparation(widget.model);
    final preparing = state.lifecycle == OfflineSpeechLifecycle.preparing;
    final repairingRuntime =
        installed && !requiresModelFiles && requiresRuntime;
    final runnable = installed && !requiresUpdate && hardwareAvailable;
    final running = state.lifecycle == OfflineSpeechLifecycle.running;
    final busy =
        _mutating ||
        _testing ||
        state.lifecycle == OfflineSpeechLifecycle.downloading ||
        preparing ||
        state.lifecycle == OfflineSpeechLifecycle.starting ||
        state.lifecycle == OfflineSpeechLifecycle.stopping;
    final accent = theme.colorScheme.primary;
    return AnimatedContainer(
      duration: openHandMotionDuration(context, kOpenHandMotion260),
      curve: kOpenHandEmphasizedCurve,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: kOpenHandBorderRadius16,
        border: Border.all(
          color: _enabled
              ? accent.withValues(alpha: 0.28)
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.72),
        ),
        color: Color.alphaBlend(
          accent.withValues(alpha: _enabled ? 0.035 : 0),
          theme.colorScheme.surfaceContainer,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Wrap(
                      spacing: 7,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        Text(
                          widget.model.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        _OfflineSpeechBadge(
                          label: widget.model.sizeLabel,
                          color: accent,
                        ),
                        _OfflineSpeechLifecycleBadge(state: state),
                        _OfflineSpeechBadge(
                          label: hardwareAvailable ? '设备可用' : '设备不可用',
                          color: hardwareAvailable
                              ? OpenHandStatusColors.success
                              : theme.colorScheme.error,
                        ),
                        if (_enabled)
                          const _OfflineSpeechBadge(
                            label: '已启用',
                            color: OpenHandStatusColors.success,
                          ),
                      ],
                    ),
                    kOpenHandGap5,
                    Text(
                      widget.model.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                    if (!hardwareAvailable) ...<Widget>[
                      kOpenHandGap5,
                      Text(
                        availability.reason,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              kOpenHandHGap8,
              Wrap(
                spacing: 8,
                runSpacing: 6,
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  _OfflineSpeechActionButton(
                    tooltip:
                        state.lifecycle == OfflineSpeechLifecycle.downloading
                        ? '正在下载模型'
                        : preparing
                        ? '正在准备隔离运行环境'
                        : !hardwareAvailable
                        ? availability.reason
                        : repairingRuntime
                        ? '补全隔离运行环境'
                        : requiresUpdate
                        ? '更新模型'
                        : installed
                        ? '移除模型'
                        : '下载模型',
                    onPressed:
                        busy ||
                            (!hardwareAvailable &&
                                (!installed || requiresUpdate))
                        ? null
                        : requiresUpdate || !installed
                        ? _showDownloadDialog
                        : _confirmRemove,
                    child:
                        state.lifecycle == OfflineSpeechLifecycle.downloading ||
                            preparing
                        ? const SizedBox.square(
                            dimension: 17,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            repairingRuntime
                                ? Icons.settings_suggest_rounded
                                : requiresUpdate
                                ? Icons.system_update_alt_rounded
                                : installed
                                ? Icons.delete_outline_rounded
                                : Icons.download_rounded,
                            size: 22,
                          ),
                  ),
                  if (requiresUpdate)
                    _OfflineSpeechActionButton(
                      tooltip: '移除模型',
                      onPressed: busy ? null : _confirmRemove,
                      child: const Icon(Icons.delete_outline_rounded, size: 22),
                    ),
                  _OfflineSpeechActionButton(
                    tooltip: !hardwareAvailable
                        ? availability.reason
                        : running
                        ? '停止模型'
                        : '运行模型',
                    onPressed: runnable && !busy
                        ? running
                              ? _stop
                              : _start
                        : null,
                    child: Icon(
                      running
                          ? Icons.stop_rounded
                          : Icons.power_settings_new_rounded,
                      size: 22,
                    ),
                  ),
                  _OfflineSpeechActionButton(
                    tooltip: hardwareAvailable ? '测试当前配置' : availability.reason,
                    onPressed: runnable && !busy ? _test : null,
                    child: _testing
                        ? const SizedBox.square(
                            dimension: 17,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.science_rounded, size: 22),
                  ),
                  _AiProviderCardExpandButton(
                    expanded: _expanded,
                    enabled: _enabled && hardwareAvailable,
                    onPressed: () {
                      setState(() => _expanded = !_expanded);
                      HapticFeedback.selectionClick();
                    },
                  ),
                  Tooltip(
                    message: !hardwareAvailable
                        ? _enabled
                              ? '设备不可用，仅可禁用模型'
                              : availability.reason
                        : runnable
                        ? (_enabled ? '禁用模型' : '启用模型')
                        : '下载当前配置后可启用',
                    child: _SettingsSwitch(
                      value: _enabled,
                      onChanged: !busy && (_enabled || runnable)
                          ? _setEnabled
                          : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
          _AnimatedSettingReveal(
            visible: hardwareAvailable && _enabled && _expanded,
            child: Padding(
              padding: const EdgeInsets.only(top: 14),
              child: _AiTtsProviderSection(
                title: '模型配置 · ${widget.model.parameters.length} 项',
                child: _AiTtsProviderFieldGrid(
                  children: <Widget>[
                    for (final parameter in widget.model.parameters)
                      _OfflineSpeechParameterField(
                        parameter: parameter,
                        value:
                            _configuration[parameter.key] ??
                            parameter.defaultValue,
                        onChanged: (value) =>
                            _updateParameter(parameter, value),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showDownloadDialog() async {
    final service = OfflineSpeechModelService.instance;
    final installed = service.isInstalled(widget.model);
    final modelFilesRequired = service.requiresModelFilesForConfiguration(
      widget.model,
      _configuration,
    );
    final runtimeRequired = service.requiresRuntimePreparation(widget.model);
    final repairingRuntime =
        installed && !modelFilesRequired && runtimeRequired;
    final action = repairingRuntime
        ? '补全运行环境'
        : installed
        ? '更新'
        : '下载';
    final runtimeNote = runtimeRequired
        ? '首次使用还会准备 ${service.runtimePreparationSizeLabel(widget.model)} 的隔离运行环境。'
        : '';
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: '$action ${widget.model.name}？',
      message: repairingRuntime
          ? '模型文件已保留。现在需要下载并验证 ${service.runtimePreparationSizeLabel(widget.model)} 的隔离运行环境，完成后即可运行。'
          : installed
          ? '模型包约 ${widget.model.sizeLabel}。更新期间会额外占用一份模型空间，完成后自动替换旧文件。'
          : '模型包约 ${widget.model.sizeLabel}，下载期间会占用网络和磁盘空间。$runtimeNote',
      confirmLabel: repairingRuntime
          ? '开始准备'
          : installed
          ? '确认更新'
          : '确认下载',
    );
    if (!confirmed || !mounted) return;
    await showOpenHandProfiledDialog<void>(
      context: context,
      barrierDismissible: false,
      dismissOnEscape: false,
      transitionProfile: const OpenHandAnimationTransitionProfile(
        fadeScaleBegin: 0.9,
        elasticScaleBegin: 0.9,
        springScaleBegin: 0.9,
        slideUpOffset: Offset(0, 0.1),
        slideDownOffset: Offset(0, -0.1),
      ),
      builder: (_) => _OfflineSpeechDownloadDialog(
        model: widget.model,
        configuration: _configuration,
      ),
    );
  }

  Future<void> _confirmRemove() async {
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: '移除 ${widget.model.name}？',
      message: '模型文件和临时数据将从本机删除。',
      confirmLabel: '移除模型',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _mutating = true);
    try {
      await OfflineSpeechModelService.instance.remove(widget.model);
      if (_enabled) await widget.onChanged(widget.settings.select(null));
      if (!mounted) return;
      showOpenHandSuccessSnack(context, '${widget.model.name} 已移除');
    } catch (error, stack) {
      silentLog('settings_offline_speech', '移除离线语音模型', error, stack);
      if (!mounted) return;
      _showOperationError('模型移除失败', error);
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<void> _start() async {
    setState(() => _mutating = true);
    try {
      await OfflineSpeechModelService.instance.start(
        widget.model,
        _configuration,
      );
      if (!mounted) return;
      showOpenHandSuccessSnack(context, '${widget.model.name} 已运行');
    } catch (error, stack) {
      silentLog('settings_offline_speech', '启动离线语音模型', error, stack);
      if (!mounted) return;
      _showOperationError('模型启动失败', error);
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<void> _stop() async {
    setState(() => _mutating = true);
    try {
      await OfflineSpeechModelService.instance.stop(widget.model);
      if (!mounted) return;
      showOpenHandInfoSnack(context, '${widget.model.name} 已停止');
    } catch (error, stack) {
      silentLog('settings_offline_speech', '停止离线语音模型', error, stack);
      if (!mounted) return;
      _showOperationError('模型停止失败', error);
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<void> _test() async {
    setState(() => _testing = true);
    try {
      await OfflineSpeechModelService.instance.test(
        widget.model,
        _configuration,
      );
      if (!mounted) return;
      showOpenHandSuccessSnack(context, '${widget.model.name} 当前配置测试通过');
    } catch (error, stack) {
      silentLog('settings_offline_speech', '测试离线语音模型', error, stack);
      if (!mounted) return;
      _showOperationError('模型测试失败', error);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _setEnabled(bool value) async {
    if (value) {
      final previous = OfflineSpeechModelCatalog.byId(
        widget.settings.enabledModelId ?? '',
      );
      if (previous != null && previous.id != widget.model.id) {
        await OfflineSpeechModelService.instance.stop(previous);
      }
    }
    final changed = await widget.onChanged(
      widget.settings.select(value ? widget.model.id : null),
    );
    if (!mounted || changed) return;
    _showOfflineSpeechPersistenceFailure(context);
  }

  Future<void> _updateParameter(
    OfflineSpeechParameter parameter,
    Object? value,
  ) async {
    final next = <String, Object?>{
      ..._configuration,
      parameter.key: parameter.normalize(value),
    };
    setState(() => _draftConfiguration = next);
    final changed = await widget.onChanged(
      widget.settings.updateConfiguration(widget.model, next),
    );
    if (!mounted || changed) return;
    _showOfflineSpeechPersistenceFailure(context);
  }

  void _showOperationError(String title, Object error) {
    _showSettingsTestErrorDialog(
      context: context,
      title: title,
      targetLabel: widget.model.name,
      error: error,
    );
  }
}

class _OfflineSpeechParameterField extends StatelessWidget {
  const _OfflineSpeechParameterField({
    required this.parameter,
    required this.value,
    required this.onChanged,
  });

  final OfflineSpeechParameter parameter;
  final Object value;
  final ValueChanged<Object?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final control = switch (parameter.type) {
      OfflineSpeechParameterType.toggle => _AiTtsToggleField(
        label: parameter.label,
        value: value as bool,
        onChanged: onChanged,
      ),
      OfflineSpeechParameterType.choice => _SettingsStringDropdown(
        label: parameter.label,
        value: '$value',
        options: <_SettingsStringDropdownOption>[
          for (final option in parameter.options)
            _SettingsStringDropdownOption(option.value, option.label),
        ],
        onChanged: onChanged,
      ),
      OfflineSpeechParameterType.integer ||
      OfflineSpeechParameterType.decimal => _AiTtsProviderNumberField(
        label: parameter.label,
        value: (value as num).toDouble(),
        range: _TtsNumberRange(
          parameter.min ?? 0,
          parameter.max ?? 100,
          step: parameter.type == OfflineSpeechParameterType.integer ? 1 : 0.05,
        ),
        onChanged: (next) => onChanged(
          parameter.type == OfflineSpeechParameterType.integer
              ? next.round()
              : next,
        ),
      ),
      OfflineSpeechParameterType.text ||
      OfflineSpeechParameterType.path => _AiTtsProviderTextField(
        label: parameter.label,
        value: '$value',
        maxLines: parameter.type == OfflineSpeechParameterType.text ? 2 : 1,
        onSubmitted: onChanged,
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        control,
        kOpenHandGap5,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            parameter.description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

class _OfflineSpeechDownloadDialog extends StatefulWidget {
  const _OfflineSpeechDownloadDialog({
    required this.model,
    required this.configuration,
  });

  final OfflineSpeechModelDefinition model;
  final Map<String, Object?> configuration;

  @override
  State<_OfflineSpeechDownloadDialog> createState() =>
      _OfflineSpeechDownloadDialogState();
}

class _OfflineSpeechDownloadDialogState
    extends State<_OfflineSpeechDownloadDialog> {
  final OfflineSpeechModelService _service = OfflineSpeechModelService.instance;
  bool _finished = false;
  bool _cancelling = false;
  bool _cancelled = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _service.addListener(_refresh);
    unawaited(_download());
  }

  @override
  void dispose() {
    _service.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _download() async {
    try {
      await _service.download(widget.model, widget.configuration);
    } on OfflineSpeechDownloadCancelled {
      _cancelled = true;
    } catch (error, stack) {
      _error = error;
      silentLog('settings_offline_speech', '下载离线语音模型', error, stack);
    } finally {
      if (mounted) {
        setState(() {
          _finished = true;
          _cancelling = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = _service.stateOf(widget.model);
    final progress = state.progress;
    final preparing = state.lifecycle == OfflineSpeechLifecycle.preparing;
    final accent = theme.colorScheme.primary;
    return PopScope(
      canPop: _finished,
      child: buildOpenHandAlertDialog(
        icon: _OfflineSpeechDialogIcon(
          accent: accent,
          finished: _finished,
          error: _error,
        ),
        title: Text(_dialogTitle),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                _finished
                    ? _resultMessage
                    : preparing
                    ? '正在为 ${widget.model.name} 准备隔离运行环境，完成前请保持网络连接。'
                    : '正在下载 ${widget.model.name}，完成前请保持网络连接。',
                style: theme.textTheme.bodyMedium,
              ),
              kOpenHandGap18,
              if (!_finished) ...<Widget>[
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: progress ?? 0),
                  duration: openHandMotionDuration(
                    context,
                    const Duration(milliseconds: 520),
                  ),
                  curve: kOpenHandEntranceCurve,
                  builder: (context, value, _) => ClipRRect(
                    borderRadius: kOpenHandBorderRadius12,
                    child: LinearProgressIndicator(
                      value: progress == null ? null : value.clamp(0, 1),
                      minHeight: 11,
                      color: accent,
                      backgroundColor: accent.withValues(alpha: 0.13),
                    ),
                  ),
                ),
                kOpenHandGap12,
                if (state.totalBytes > 0 || state.totalFiles > 0)
                  Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: <Widget>[
                      _OfflineSpeechMetric(
                        icon: Icons.data_usage_rounded,
                        text: state.totalBytes > 0
                            ? '${formatByteSize(state.receivedBytes)} / ${formatByteSize(state.totalBytes)}'
                            : formatByteSize(state.receivedBytes),
                      ),
                      _OfflineSpeechMetric(
                        icon: Icons.speed_rounded,
                        text: '${formatByteSize(state.bytesPerSecond)}/s',
                      ),
                      _OfflineSpeechMetric(
                        icon: Icons.inventory_2_outlined,
                        text:
                            '${state.completedFiles} / ${state.totalFiles} 个文件',
                      ),
                    ],
                  ),
                if (state.message != null) ...<Widget>[
                  kOpenHandGap10,
                  Text(
                    state.message!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (_cancelling) ...<Widget>[
                  kOpenHandGap12,
                  const Row(
                    children: <Widget>[
                      SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      kOpenHandHGap8,
                      Expanded(child: Text('正在终止下载并清理临时文件…')),
                    ],
                  ),
                ],
              ],
            ],
          ),
        ),
        actions: <Widget>[
          if (_finished)
            OpenHandDialogActionButton.primary(
              onPressed: () => Navigator.of(context).pop(),
              label: '完成',
            )
          else
            OpenHandDialogActionButton.destructive(
              onPressed: _cancelling ? null : _confirmCancel,
              label: '强制取消',
            ),
        ],
      ),
    );
  }

  String get _dialogTitle {
    if (!_finished) {
      if (_cancelling) return '正在取消任务';
      return _service.stateOf(widget.model).lifecycle ==
              OfflineSpeechLifecycle.preparing
          ? '准备隔离运行环境'
          : '下载离线模型';
    }
    if (_cancelled) return '下载已取消';
    if (_error != null) return '下载失败';
    return '模型已就绪';
  }

  String get _resultMessage {
    if (_cancelled) return '任务已停止，未完成的临时数据已清理，完整模型文件已保留。';
    if (_error != null) return '$_error';
    return '${widget.model.name} 及隔离运行环境已准备完成，可以启用并运行。';
  }

  Future<void> _confirmCancel() async {
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: '强制取消当前任务？',
      message: '当前任务会立即终止，未完成的临时数据将同步清理，已经完整下载的模型文件会保留。',
      confirmLabel: '取消并清理',
      destructive: true,
      barrierDismissible: false,
    );
    if (!confirmed || !mounted) return;
    setState(() => _cancelling = true);
    _service.cancelDownload(widget.model);
  }
}

class _OfflineSpeechDialogIcon extends StatelessWidget {
  const _OfflineSpeechDialogIcon({
    required this.accent,
    required this.finished,
    required this.error,
  });

  final Color accent;
  final bool finished;
  final Object? error;

  @override
  Widget build(BuildContext context) {
    final color = error != null
        ? Theme.of(context).colorScheme.error
        : finished
        ? OpenHandStatusColors.success
        : accent;
    return AnimatedContainer(
      duration: openHandMotionDuration(context, kOpenHandMotion260),
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.14),
      ),
      child: AnimatedSwitcher(
        duration: openHandMotionDuration(context, kOpenHandMotion220),
        child: Icon(
          error != null
              ? Icons.error_outline_rounded
              : finished
              ? Icons.check_circle_outline_rounded
              : Icons.cloud_download_rounded,
          key: ValueKey<Object?>(error ?? finished),
          color: color,
        ),
      ),
    );
  }
}

class _OfflineSpeechMetric extends StatelessWidget {
  const _OfflineSpeechMetric({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        kOpenHandHGap5,
        Text(text, style: theme.textTheme.labelMedium),
      ],
    );
  }
}

class _OfflineSpeechHardwareSummary extends StatelessWidget {
  const _OfflineSpeechHardwareSummary({required this.profile});

  final OfflineSpeechHardwareProfile? profile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = profile;
    final text = current == null
        ? '正在自动评估处理器、内存和磁盘…'
        : !current.platformSupported
        ? '当前平台不支持本地模型运行时'
        : '${current.architecture} · ${current.logicalCores} 核 · '
              '${formatByteSize(current.totalMemoryBytes)} 内存 · '
              '${formatByteSize(current.freeStorageBytes)} 可用空间';
    return Row(
      children: <Widget>[
        Icon(
          current == null
              ? Icons.memory_rounded
              : current.platformSupported
              ? Icons.check_circle_outline_rounded
              : Icons.block_rounded,
          size: 15,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        kOpenHandHGap5,
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _OfflineSpeechActionButton extends StatelessWidget {
  const _OfflineSpeechActionButton({
    required this.tooltip,
    required this.onPressed,
    required this.child,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox.square(
        dimension: _aiTtsCardActionSize,
        child: IconButton.filledTonal(
          onPressed: onPressed,
          style: _aiCardActionButtonStyle(Theme.of(context)),
          icon: child,
        ),
      ),
    );
  }
}

class _OfflineSpeechBadge extends StatelessWidget {
  const _OfflineSpeechBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: kOpenHandPillBorderRadius,
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _OfflineSpeechLifecycleBadge extends StatelessWidget {
  const _OfflineSpeechLifecycleBadge({required this.state});

  final OfflineSpeechModelState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, color) = switch (state.lifecycle) {
      OfflineSpeechLifecycle.absent => (
        '未下载',
        theme.colorScheme.onSurfaceVariant,
      ),
      OfflineSpeechLifecycle.downloading => ('下载中', theme.colorScheme.primary),
      OfflineSpeechLifecycle.preparing => ('准备中', theme.colorScheme.tertiary),
      OfflineSpeechLifecycle.installed => ('已下载', OpenHandStatusColors.info),
      OfflineSpeechLifecycle.starting => ('启动中', theme.colorScheme.tertiary),
      OfflineSpeechLifecycle.running => ('运行中', OpenHandStatusColors.success),
      OfflineSpeechLifecycle.stopping => ('停止中', theme.colorScheme.tertiary),
      OfflineSpeechLifecycle.failed => ('异常', theme.colorScheme.error),
    };
    return _OfflineSpeechBadge(label: label, color: color);
  }
}

void _showOfflineSpeechPersistenceFailure(BuildContext context) {
  showOpenHandErrorSnack(
    context,
    AppLocalizations.of(context)!.settingsPersistenceSaveFailedBody,
  );
}

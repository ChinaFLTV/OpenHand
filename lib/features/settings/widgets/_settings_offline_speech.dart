part of 'settings_view.dart';

const double _offlineSpeechPanelMaxHeight = 680;
const double _offlineSpeechCardActionSize = 40;

class _OfflineSpeechModelPanel extends StatelessWidget {
  const _OfflineSpeechModelPanel({
    required this.kind,
    required this.settings,
    required this.onChanged,
  });

  final OfflineSpeechKind kind;
  final OfflineSpeechModelSettings settings;
  final Future<bool> Function(OfflineSpeechModelSettings settings) onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final models = OfflineSpeechModelCatalog.forKind(kind);
    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxHeight: _offlineSpeechPanelMaxHeight,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLowest.withValues(
            alpha: 0.72,
          ),
          borderRadius: kOpenHandBorderRadius16,
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.52),
          ),
        ),
        child: OpenHandSafeScrollbar(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: AnimatedBuilder(
              animation: OfflineSpeechModelService.instance,
              builder: (context, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _OfflineSpeechPanelHeader(
                    kind: kind,
                    modelCount: models.length,
                  ),
                  kOpenHandGap14,
                  for (
                    var index = 0;
                    index < models.length;
                    index++
                  ) ...<Widget>[
                    _OfflineSpeechModelCard(
                      key: ValueKey<String>(
                        'offlineSpeechModel-${models[index].id}',
                      ),
                      model: models[index],
                      settings: settings,
                      onChanged: onChanged,
                    ),
                    if (index != models.length - 1) kOpenHandGap12,
                  ],
                ],
              ),
            ),
          ),
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            borderRadius: kOpenHandBorderRadius14,
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.68),
            border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.18),
            ),
          ),
          child: Icon(
            isRecognition
                ? Icons.graphic_eq_rounded
                : Icons.record_voice_over_rounded,
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
        kOpenHandHGap12,
        Expanded(
          child: Column(
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
          ),
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
    final runnable = installed && !requiresUpdate && hardwareAvailable;
    final running = state.lifecycle == OfflineSpeechLifecycle.running;
    final busy =
        _mutating ||
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
              _OfflineSpeechModelIcon(model: widget.model, running: running),
              kOpenHandHGap12,
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
            ],
          ),
          kOpenHandGap12,
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              if (state.lifecycle == OfflineSpeechLifecycle.downloading)
                FilledButton.tonalIcon(
                  onPressed: null,
                  icon: const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  label: const Text('下载中'),
                )
              else if (requiresUpdate)
                FilledButton.tonalIcon(
                  onPressed: busy || !hardwareAvailable
                      ? null
                      : _showDownloadDialog,
                  icon: const Icon(Icons.system_update_alt_rounded),
                  label: const Text('更新模型'),
                )
              else if (installed)
                OutlinedButton.icon(
                  onPressed: busy ? null : _confirmRemove,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('移除'),
                )
              else
                FilledButton.tonalIcon(
                  onPressed: busy || !hardwareAvailable
                      ? null
                      : _showDownloadDialog,
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('下载'),
                ),
              if (requiresUpdate)
                OutlinedButton.icon(
                  onPressed: busy ? null : _confirmRemove,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('移除'),
                ),
              FilledButton.tonalIcon(
                onPressed: runnable && !busy
                    ? running
                          ? _stop
                          : _start
                    : null,
                icon: Icon(
                  running
                      ? Icons.stop_rounded
                      : Icons.power_settings_new_rounded,
                ),
                label: Text(running ? '停止' : '运行'),
              ),
              _OfflineSpeechActionButton(
                tooltip: '测试当前配置',
                onPressed: runnable && !busy && !_testing ? _test : null,
                child: _testing
                    ? const SizedBox.square(
                        dimension: 17,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.science_rounded),
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
                      text: '${state.completedFiles} / ${state.totalFiles} 个文件',
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
    if (!_finished) return _cancelling ? '正在取消下载' : '下载离线模型';
    if (_cancelled) return '下载已取消';
    if (_error != null) return '下载失败';
    return '模型已就绪';
  }

  String get _resultMessage {
    if (_cancelled) return '下载已停止，所有未完成的模型数据均已清理。';
    if (_error != null) return '$_error';
    return '${widget.model.name} 已完整下载到本地，可以启用并运行。';
  }

  Future<void> _confirmCancel() async {
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: '强制取消下载？',
      message: '下载会立即终止，已经写入的模型文件将同步清理。',
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

class _OfflineSpeechModelIcon extends StatelessWidget {
  const _OfflineSpeechModelIcon({required this.model, required this.running});

  final OfflineSpeechModelDefinition model;
  final bool running;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: openHandMotionDuration(context, kOpenHandMotion260),
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        borderRadius: kOpenHandBorderRadius12,
        color: Theme.of(
          context,
        ).colorScheme.primaryContainer.withValues(alpha: running ? 0.86 : 0.68),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.18),
        ),
      ),
      child: Icon(
        model.kind == OfflineSpeechKind.recognition
            ? Icons.mic_rounded
            : Icons.spatial_audio_off_rounded,
        color: Theme.of(context).colorScheme.onPrimaryContainer,
      ),
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
        dimension: _offlineSpeechCardActionSize,
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

part of 'settings_view.dart';

const int _aiModelChipPreviewLimit = 8;
const String _settingsZeroDurationLabel = '0s';

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
    final motionDisabled = MediaQuery.disableAnimationsOf(context);
    final body = Column(
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
        if (motionDisabled)
          child
        else
          ClipRect(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 420),
              reverseDuration: const Duration(milliseconds: 260),
              curve: Curves.easeOutBack,
              alignment: Alignment.topCenter,
              child: child,
            ),
          ),
      ],
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Padding(padding: const EdgeInsets.all(18), child: body),
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
    this.subtitle,
    required this.control,
    this.controlMaxWidth = 320,
  });

  final String title;
  final String? subtitle;
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
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
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
                  if (subtitle != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      subtitle!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
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

class _SettingsSwitch extends StatelessWidget {
  const _SettingsSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Switch(
      value: value,
      onChanged: onChanged,
      thumbIcon: WidgetStateProperty.resolveWith<Icon?>((states) {
        if (states.contains(WidgetState.disabled)) {
          return const Icon(Icons.lock_outline_rounded, size: 16);
        }
        if (states.contains(WidgetState.selected)) {
          return const Icon(Icons.check_rounded, size: 16);
        }
        return const Icon(Icons.close_rounded, size: 16);
      }),
    );
  }
}

class _AiTtsSettingsPanel extends StatelessWidget {
  const _AiTtsSettingsPanel({
    required this.settings,
    required this.onChanged,
    required this.playbackService,
  });

  final AiTtsSettings settings;
  final Future<bool> Function(AiTtsSettings settings) onChanged;
  final AiTtsPlaybackService playbackService;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 560),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLowest.withValues(
            alpha: 0.72,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.52),
          ),
        ),
        child: OpenHandSafeScrollbar(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ResponsiveSettingRow(
                  title: _localizedText(
                    context,
                    zh: '朗读超时',
                    en: 'Read Timeout',
                  ),
                  subtitle: _localizedText(
                    context,
                    zh: '单次朗读或服务调用的最长等待秒数，防止无限等待。',
                    en: 'Maximum seconds for one read attempt.',
                  ),
                  control: _SettingsIntField(
                    value: settings.timeoutSeconds,
                    min: AiTtsSettings.minTimeoutSeconds,
                    max: AiTtsSettings.maxTimeoutSeconds,
                    onChanged: (value) =>
                        onChanged(settings.copyWith(timeoutSeconds: value)),
                  ),
                ),
                const SizedBox(height: 16),
                _ResponsiveSettingRow(
                  title: _localizedText(
                    context,
                    zh: '最大朗读字符',
                    en: 'Max Read Characters',
                  ),
                  subtitle: _localizedText(
                    context,
                    zh: '超出后自动截断，避免长消息占用朗读资源过久。',
                    en: 'Long messages are truncated to keep playback bounded.',
                  ),
                  control: _SettingsIntField(
                    value: settings.maxTextCharacters,
                    min: AiTtsSettings.minMaxTextCharacters,
                    max: AiTtsSettings.maxMaxTextCharacters,
                    onChanged: (value) =>
                        onChanged(settings.copyWith(maxTextCharacters: value)),
                  ),
                ),
                const SizedBox(height: 16),
                _AiTtsProviderDeck(
                  settings: settings,
                  onChanged: onChanged,
                  playbackService: playbackService,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AiTtsProviderDeck extends StatelessWidget {
  const _AiTtsProviderDeck({
    required this.settings,
    required this.onChanged,
    required this.playbackService,
  });

  final AiTtsSettings settings;
  final Future<bool> Function(AiTtsSettings settings) onChanged;
  final AiTtsPlaybackService playbackService;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _localizedText(context, zh: 'TTS 服务优先级', en: 'TTS Priority'),
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        Text(
          _localizedText(
            context,
            zh: '拖动下方服务卡片调整优先级；不可用或超时时自动回退。',
            en: 'Drag provider cards to set priority; unavailable services fall back.',
          ),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        Theme(
          data: theme.copyWith(
            canvasColor: Colors.transparent,
            shadowColor: Colors.transparent,
          ),
          child: ReorderableListView.builder(
            buildDefaultDragHandles: false,
            primary: false,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            proxyDecorator: (child, index, animation) {
              return AnimatedBuilder(
                animation: animation,
                builder: (context, _) {
                  final t = Curves.easeOutBack.transform(
                    animation.value.clamp(0.0, 1.0),
                  );
                  return Transform.scale(
                    scale: 1 + 0.018 * t,
                    child: Material(
                      type: MaterialType.transparency,
                      child: child,
                    ),
                  );
                },
              );
            },
            itemCount: settings.providerPriority.length,
            onReorder: (oldIndex, newIndex) {
              final next = List<AiTtsProvider>.from(settings.providerPriority);
              var target = newIndex;
              if (target > oldIndex) target -= 1;
              if (oldIndex == target) return;
              final item = next.removeAt(oldIndex);
              next.insert(target, item);
              onChanged(settings.copyWith(providerPriority: next));
            },
            itemBuilder: (context, index) {
              final provider = settings.providerPriority[index];
              return Padding(
                key: ValueKey<String>('tts-provider-${provider.storageKey}'),
                padding: EdgeInsets.only(
                  bottom: index == settings.providerPriority.length - 1
                      ? 0
                      : 12,
                ),
                child: _AiTtsProviderCard(
                  settings: settings,
                  provider: provider,
                  priorityIndex: index,
                  onChanged: onChanged,
                  playbackService: playbackService,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AiTtsProviderCard extends StatefulWidget {
  const _AiTtsProviderCard({
    required this.settings,
    required this.provider,
    required this.priorityIndex,
    required this.onChanged,
    required this.playbackService,
  });

  final AiTtsSettings settings;
  final AiTtsProvider provider;
  final int priorityIndex;
  final Future<bool> Function(AiTtsSettings settings) onChanged;
  final AiTtsPlaybackService playbackService;

  @override
  State<_AiTtsProviderCard> createState() => _AiTtsProviderCardState();
}

class _AiTtsProviderCardState extends State<_AiTtsProviderCard> {
  bool _testing = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = widget.provider;
    final providerSettings = widget.settings.provider(provider);
    final catalog = AiTtsProviderCatalogs.of(provider);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: providerSettings.enabled
              ? theme.colorScheme.primary.withValues(alpha: 0.28)
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.72),
        ),
        color: Color.alphaBlend(
          theme.colorScheme.primary.withValues(
            alpha: providerSettings.enabled ? 0.035 : 0,
          ),
          theme.colorScheme.surfaceContainer,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ReorderableDragStartListener(
                index: widget.priorityIndex,
                child: Tooltip(
                  message: _localizedText(context, zh: '拖动调整优先级', en: 'Drag'),
                  child: Container(
                    width: 34,
                    height: 34,
                    margin: const EdgeInsets.only(right: 10, top: 1),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: theme.colorScheme.surfaceContainerHigh,
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant.withValues(
                          alpha: 0.74,
                        ),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.drag_indicator_rounded,
                      size: 20,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _AiTtsPriorityBadge(index: widget.priorityIndex),
                        Text(
                          _ttsProviderLabel(context, provider),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        _AiTtsStatusBadge(enabled: providerSettings.enabled),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _ttsProviderHint(context, provider),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.end,
                children: [
                  _AiTtsTestButton(
                    testing: _testing,
                    onPressed: _testing ? null : _testProvider,
                  ),
                  _SettingsSwitch(
                    value: providerSettings.enabled,
                    onChanged: (value) =>
                        _update(providerSettings.copyWith(enabled: value)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          _AnimatedSettingReveal(
            visible: providerSettings.enabled,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _AiTtsProviderSection(
                  title: _localizedText(context, zh: '声音参数', en: 'Voice'),
                  child: _AiTtsProviderFieldGrid(
                    children: [
                      _AiTtsDropdown(
                        label: _localizedText(
                          context,
                          zh: '音色/发音人',
                          en: 'Voice',
                        ),
                        value: providerSettings.voice,
                        options: catalog.voiceOptions,
                        onChanged: (value) =>
                            _update(providerSettings.copyWith(voice: value)),
                      ),
                      _AiTtsDropdown(
                        label: _localizedText(
                          context,
                          zh: '语言',
                          en: 'Language',
                        ),
                        value: providerSettings.language,
                        options: catalog.languageOptions,
                        onChanged: (value) =>
                            _update(providerSettings.copyWith(language: value)),
                      ),
                      _AiTtsProviderNumberField(
                        label: _localizedText(context, zh: '语速', en: 'Speed'),
                        value: providerSettings.speed,
                        onChanged: (value) =>
                            _update(providerSettings.copyWith(speed: value)),
                      ),
                      _AiTtsProviderNumberField(
                        label: _localizedText(context, zh: '音量', en: 'Volume'),
                        value: providerSettings.volume,
                        onChanged: (value) =>
                            _update(providerSettings.copyWith(volume: value)),
                      ),
                      _AiTtsProviderNumberField(
                        label: _localizedText(context, zh: '音调', en: 'Pitch'),
                        value: providerSettings.pitch,
                        onChanged: (value) =>
                            _update(providerSettings.copyWith(pitch: value)),
                      ),
                    ],
                  ),
                ),
                if (_providerNeedsEndpoint(provider) ||
                    _providerNeedsCredentials(provider)) ...[
                  const SizedBox(height: 12),
                  _AiTtsProviderSection(
                    title: _localizedText(context, zh: '连接与凭据', en: 'Access'),
                    child: _AiTtsProviderFieldGrid(
                      children: [
                        if (_providerNeedsEndpoint(provider))
                          _AiTtsProviderTextField(
                            label: _localizedText(
                              context,
                              zh: '接口地址',
                              en: 'Endpoint',
                            ),
                            value: providerSettings.endpoint,
                            onSubmitted: (value) => _update(
                              providerSettings.copyWith(endpoint: value),
                            ),
                          ),
                        if (_providerNeedsCredentials(provider) &&
                            provider != AiTtsProvider.baidu &&
                            provider != AiTtsProvider.doubao)
                          _AiTtsProviderTextField(
                            label: 'App ID',
                            value: providerSettings.appId,
                            onSubmitted: (value) => _update(
                              providerSettings.copyWith(appId: value),
                            ),
                          ),
                        if (_providerNeedsCredentials(provider))
                          _AiTtsProviderTextField(
                            label: provider == AiTtsProvider.baidu
                                ? 'Access Token'
                                : 'API Key',
                            value: provider == AiTtsProvider.baidu
                                ? providerSettings.accessToken
                                : providerSettings.apiKey,
                            obscure: true,
                            onSubmitted: (value) =>
                                provider == AiTtsProvider.baidu
                                ? _update(
                                    providerSettings.copyWith(
                                      accessToken: value,
                                    ),
                                  )
                                : _update(
                                    providerSettings.copyWith(apiKey: value),
                                  ),
                          ),
                        if (_providerNeedsCredentials(provider) &&
                            provider != AiTtsProvider.baidu &&
                            provider != AiTtsProvider.doubao)
                          _AiTtsProviderTextField(
                            label: 'API Secret / Token',
                            value: providerSettings.apiSecret,
                            obscure: true,
                            onSubmitted: (value) => _update(
                              providerSettings.copyWith(apiSecret: value),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                if (provider == AiTtsProvider.doubao) ...[
                  const SizedBox(height: 12),
                  _AiTtsProviderSection(
                    title: _localizedText(context, zh: '豆包参数', en: 'Doubao'),
                    child: _AiTtsProviderFieldGrid(
                      children: [
                        _AiTtsExtraDropdown(
                          label: 'Resource ID',
                          value:
                              '${providerSettings.extra['resource_id'] ?? 'seed-tts-2.0'}',
                          options: catalog.resourceIdOptions,
                          onChanged: (value) => _updateExtra(
                            providerSettings,
                            'resource_id',
                            value,
                          ),
                        ),
                        _AiTtsExtraDropdown(
                          label: _localizedText(context, zh: '模型', en: 'Model'),
                          value:
                              '${providerSettings.extra['model'] ?? 'seed-tts-2.0-standard'}',
                          options: catalog.modelOptions,
                          onChanged: (value) =>
                              _updateExtra(providerSettings, 'model', value),
                        ),
                        _AiTtsExtraDropdown(
                          label: _localizedText(
                            context,
                            zh: '音频格式',
                            en: 'Format',
                          ),
                          value: '${providerSettings.extra['format'] ?? 'mp3'}',
                          options: catalog.formatOptions,
                          onChanged: (value) =>
                              _updateExtra(providerSettings, 'format', value),
                        ),
                      ],
                    ),
                  ),
                ] else if (provider == AiTtsProvider.xfyun) ...[
                  const SizedBox(height: 12),
                  _AiTtsProviderSection(
                    title: _localizedText(context, zh: '音频编码', en: 'Audio'),
                    child: _AiTtsProviderFieldGrid(
                      children: [
                        _AiTtsExtraDropdown(
                          label: _localizedText(
                            context,
                            zh: '音频格式',
                            en: 'Format',
                          ),
                          value: '${providerSettings.extra['aue'] ?? 'lame'}',
                          options: catalog.formatOptions,
                          onChanged: (value) =>
                              _updateExtra(providerSettings, 'aue', value),
                        ),
                      ],
                    ),
                  ),
                ] else if (provider == AiTtsProvider.google) ...[
                  const SizedBox(height: 12),
                  _AiTtsProviderSection(
                    title: _localizedText(context, zh: '音频编码', en: 'Audio'),
                    child: _AiTtsProviderFieldGrid(
                      children: [
                        _AiTtsExtraDropdown(
                          label: _localizedText(
                            context,
                            zh: '音频格式',
                            en: 'Format',
                          ),
                          value:
                              '${providerSettings.extra['audioEncoding'] ?? 'MP3'}',
                          options: catalog.formatOptions,
                          onChanged: (value) => _updateExtra(
                            providerSettings,
                            'audioEncoding',
                            value,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _testProvider() async {
    if (_testing) return;
    setState(() => _testing = true);
    try {
      await widget.playbackService.testProvider(
        settings: widget.settings.copyWith(enabled: true),
        provider: widget.provider,
      );
      if (!mounted) return;
      OpenHandSnackBar.show(
        context,
        ScaffoldMessenger.of(context),
        OpenHandSnackBar.success(
          context,
          _localizedText(context, zh: 'TTS 测试播放完成', en: 'TTS test played'),
        ),
      );
    } catch (error, stack) {
      silentLog(
        'tts-settings',
        'test ${widget.provider.storageKey}',
        error,
        stack,
      );
      if (!mounted) return;
      OpenHandSnackBar.show(
        context,
        ScaffoldMessenger.of(context),
        OpenHandSnackBar.error(
          context,
          _localizedText(
            context,
            zh: 'TTS 测试失败：${_friendlyTtsError(error)}',
            en: 'TTS test failed: ${_friendlyTtsError(error)}',
          ),
          maxLines: 2,
        ),
      );
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _update(AiTtsProviderSettings next) async {
    final providers = Map<AiTtsProvider, AiTtsProviderSettings>.from(
      widget.settings.providers,
    );
    providers[widget.provider] = next.normalized();
    await widget.onChanged(widget.settings.copyWith(providers: providers));
  }

  Future<void> _updateExtra(
    AiTtsProviderSettings current,
    String key,
    Object? value,
  ) async {
    final extra = Map<String, Object?>.from(current.extra);
    extra[key] = value;
    await _update(current.copyWith(extra: extra));
  }
}

class _AiTtsPriorityBadge extends StatelessWidget {
  const _AiTtsPriorityBadge({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.78),
      ),
      child: Text(
        '#${index + 1}',
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _AiTtsStatusBadge extends StatelessWidget {
  const _AiTtsStatusBadge({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = enabled
        ? OpenHandStatusColors.success
        : theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Text(
        enabled
            ? _localizedText(context, zh: '启用', en: 'On')
            : _localizedText(context, zh: '停用', en: 'Off'),
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _AiTtsTestButton extends StatelessWidget {
  const _AiTtsTestButton({required this.testing, required this.onPressed});

  final bool testing;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: _localizedText(context, zh: '测试 TTS 服务', en: 'Test TTS'),
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 34),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
        ),
        icon: testing
            ? const SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.play_circle_outline_rounded, size: 17),
        label: Text(
          testing
              ? _localizedText(context, zh: '测试中', en: 'Testing')
              : _localizedText(context, zh: '测试', en: 'Test'),
        ),
      ),
    );
  }
}

class _AiTtsProviderSection extends StatelessWidget {
  const _AiTtsProviderSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.58),
        ),
        color: theme.colorScheme.surfaceContainerLowest.withValues(alpha: 0.58),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _AiTtsProviderFieldGrid extends StatelessWidget {
  const _AiTtsProviderFieldGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 560 ? 1 : 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final child in children)
              SizedBox(
                width: columns == 1
                    ? constraints.maxWidth
                    : (constraints.maxWidth - 12) / 2,
                child: child,
              ),
          ],
        );
      },
    );
  }
}

class _AiTtsDropdown extends StatelessWidget {
  const _AiTtsDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<AiTtsCatalogOption> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final normalized = value.trim();
    final hasValue = options.any((option) => option.value == normalized);
    final effectiveOptions = options.isEmpty
        ? <AiTtsCatalogOption>[
            AiTtsCatalogOption(
              normalized,
              normalized.isEmpty
                  ? _localizedText(context, zh: '默认', en: 'Default')
                  : normalized,
            ),
          ]
        : hasValue || normalized.isEmpty
        ? options
        : <AiTtsCatalogOption>[
            AiTtsCatalogOption(
              normalized,
              _localizedText(
                context,
                zh: '当前配置：$normalized',
                en: 'Current: $normalized',
              ),
            ),
            ...options,
          ];
    final selected =
        effectiveOptions.any((option) => option.value == normalized)
        ? normalized
        : effectiveOptions.first.value;
    return DropdownButtonFormField<String>(
      initialValue: selected,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final option in effectiveOptions)
          DropdownMenuItem<String>(
            value: option.value,
            child: Text(option.label, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (value) {
        if (value == null || value == normalized) return;
        onChanged(value);
      },
    );
  }
}

class _AiTtsExtraDropdown extends StatelessWidget {
  const _AiTtsExtraDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<AiTtsCatalogOption> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return _AiTtsDropdown(
      label: label,
      value: value,
      options: options,
      onChanged: onChanged,
    );
  }
}

class _AiTtsProviderTextField extends StatefulWidget {
  const _AiTtsProviderTextField({
    required this.label,
    required this.value,
    required this.onSubmitted,
    this.obscure = false,
  });

  final String label;
  final String value;
  final ValueChanged<String> onSubmitted;
  final bool obscure;

  @override
  State<_AiTtsProviderTextField> createState() =>
      _AiTtsProviderTextFieldState();
}

class _AiTtsProviderTextFieldState extends State<_AiTtsProviderTextField> {
  late final TextEditingController _controller;
  String? _lastCommittedValue;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _AiTtsProviderTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && _controller.text != widget.value) {
      _syncControllerText(_controller, widget.value);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      decoration: InputDecoration(labelText: widget.label),
      obscureText: widget.obscure,
      enableSuggestions: !widget.obscure,
      autocorrect: !widget.obscure,
      onSubmitted: _commit,
      onEditingComplete: () => _commit(_controller.text),
    );
  }

  void _commit(String raw) {
    final value = raw.trim();
    if (value == _lastCommittedValue || value == widget.value) return;
    _lastCommittedValue = value;
    widget.onSubmitted(value);
  }
}

class _AiTtsProviderNumberField extends StatelessWidget {
  const _AiTtsProviderNumberField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: value.toStringAsFixed(
        value.truncateToDouble() == value ? 0 : 2,
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label),
      onFieldSubmitted: (raw) {
        final parsed = double.tryParse(raw.trim());
        if (parsed != null) onChanged(parsed);
      },
    );
  }
}

String _ttsProviderLabel(BuildContext context, AiTtsProvider provider) {
  switch (provider) {
    case AiTtsProvider.system:
      return _localizedText(context, zh: '系统 TTS', en: 'System TTS');
    case AiTtsProvider.xfyun:
      return _localizedText(context, zh: '讯飞 TTS', en: 'Xfyun TTS');
    case AiTtsProvider.youdao:
      return _localizedText(context, zh: '有道 TTS', en: 'Youdao TTS');
    case AiTtsProvider.bing:
      return 'Bing TTS';
    case AiTtsProvider.google:
      return 'Google TTS';
    case AiTtsProvider.baidu:
      return _localizedText(context, zh: '百度 TTS', en: 'Baidu TTS');
    case AiTtsProvider.doubao:
      return _localizedText(context, zh: '豆包 TTS', en: 'Doubao TTS');
    case AiTtsProvider.apple:
      return _localizedText(context, zh: '苹果 TTS', en: 'Apple TTS');
  }
}

String _ttsProviderHint(BuildContext context, AiTtsProvider provider) {
  switch (provider) {
    case AiTtsProvider.system:
      return _localizedText(
        context,
        zh: '默认使用本机系统语音能力，无需密钥。',
        en: 'Uses local system speech without credentials.',
      );
    case AiTtsProvider.apple:
      return _localizedText(
        context,
        zh: '在 Apple 平台优先匹配系统语音；其他平台会按能力回退。',
        en: 'Prefers Apple system voices and falls back by capability.',
      );
    case AiTtsProvider.xfyun:
      return _localizedText(
        context,
        zh: '讯飞在线 TTS，使用 WebSocket 与 HMAC 鉴权。',
        en: 'Xfyun online TTS with WebSocket and HMAC auth.',
      );
    case AiTtsProvider.youdao:
      return _localizedText(
        context,
        zh: '保留有道 TTS 参数；服务接入不可用时自动回退。',
        en: 'Keeps Youdao TTS parameters and falls back when unavailable.',
      );
    case AiTtsProvider.bing:
      return _localizedText(
        context,
        zh: '保留 Bing 语音参数；浏览器端可由系统语音兜底。',
        en: 'Keeps Bing voice parameters; browser runtime can fallback.',
      );
    case AiTtsProvider.google:
      return _localizedText(
        context,
        zh: '保留 Google TTS 参数；服务不可用时自动回退。',
        en: 'Keeps Google TTS parameters and falls back when unavailable.',
      );
    case AiTtsProvider.baidu:
      return _localizedText(
        context,
        zh: '填写 Access Token 后可调用百度语音合成接口。',
        en: 'Uses Baidu speech synthesis with an access token.',
      );
    case AiTtsProvider.doubao:
      return _localizedText(
        context,
        zh: '豆包 V3 在线语音合成，需 API Key、Resource ID 与音色。',
        en: 'Doubao V3 online TTS with API key, resource ID, and speaker.',
      );
  }
}

String _friendlyTtsError(Object error) {
  final message = error.toString().replaceFirst(RegExp(r'^[^:]+:\s*'), '');
  final normalized = message.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.isEmpty) return 'unknown error';
  const maxLength = 140;
  if (normalized.length <= maxLength) return normalized;
  return '${normalized.substring(0, maxLength)}...';
}

bool _providerNeedsEndpoint(AiTtsProvider provider) {
  return provider == AiTtsProvider.xfyun ||
      provider == AiTtsProvider.baidu ||
      provider == AiTtsProvider.doubao;
}

bool _providerNeedsCredentials(AiTtsProvider provider) {
  return provider != AiTtsProvider.system && provider != AiTtsProvider.apple;
}

class _SettingsIntField extends StatefulWidget {
  const _SettingsIntField({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  State<_SettingsIntField> createState() => _SettingsIntFieldState();
}

class _SettingsIntFieldState extends State<_SettingsIntField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.value}');
  }

  @override
  void didUpdateWidget(covariant _SettingsIntField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value &&
        _controller.text != '${widget.value}') {
      _syncControllerText(_controller, '${widget.value}');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _commit(String raw) {
    final trimmed = raw.trim();
    final parsed = optionalIntFromText(trimmed);
    if (parsed == null) {
      _syncControllerText(_controller, '${widget.value}');
      return;
    }
    final clamped = clampedIntFromText(
      trimmed,
      fallback: widget.value,
      min: widget.min,
      max: widget.max,
    );
    if (clamped != widget.value) {
      widget.onChanged(clamped);
    }
    if ('$clamped' != trimmed) {
      _syncControllerText(_controller, '$clamped');
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.right,
      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
      decoration: const InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        border: OutlineInputBorder(),
      ),
      onSubmitted: _commit,
      onEditingComplete: () => _commit(_controller.text),
    );
  }
}

class _SettingsStatusChip extends StatelessWidget {
  const _SettingsStatusChip({
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final IconData icon;
  final String label;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: foregroundColor),
          const SizedBox(width: 3),
          Text(label, style: TextStyle(color: foregroundColor, fontSize: 11)),
        ],
      ),
    );
  }
}

String _settingsFormatRemainingUntilMs(int? untilMs) {
  if (untilMs == null) return _settingsZeroDurationLabel;
  final remainingMs = untilMs - DateTime.now().millisecondsSinceEpoch;
  if (remainingMs <= 0) return _settingsZeroDurationLabel;
  if (remainingMs < Duration.millisecondsPerMinute) {
    return '${(remainingMs / Duration.millisecondsPerSecond).round()}s';
  }
  if (remainingMs < Duration.millisecondsPerHour) {
    return '${(remainingMs / Duration.millisecondsPerMinute).round()}m';
  }
  return '${(remainingMs / Duration.millisecondsPerHour).round()}h';
}

String _settingsFormatMonthDayHmsFromEpochMs(int timestampMs) {
  return formatMonthDayHms(DateTime.fromMillisecondsSinceEpoch(timestampMs));
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
            return AnimatedBuilder(
              animation: animation,
              builder: (context, _) {
                final raw = animation.value.clamp(0.0, 1.0);
                final eased = animation.status == AnimationStatus.reverse
                    ? Curves.easeInCubic.transform(raw)
                    : Curves.easeOutBack.transform(raw);
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: AlwaysStoppedAnimation<Offset>(
                      Offset(0, -0.018 * (1.0 - eased)),
                    ),
                    child: ScaleTransition(
                      scale: AlwaysStoppedAnimation<double>(
                        0.985 + 0.015 * eased,
                      ),
                      alignment: Alignment.topCenter,
                      child: transitionChild,
                    ),
                  ),
                );
              },
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
      final raw = animation.value.clamp(0.0, 1.0);
      final t = reduceMotion ? 1.0 : Curves.easeOutBack.transform(raw);
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
    super.key,
    required this.model,
    required this.isSelected,
    required this.isTesting,
    required this.isFirst,
    required this.isLast,
    required this.actionsEnabled,
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
  final bool actionsEnabled;
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

  List<String> _resolveStableChipOrder(
    List<String> allModels,
    String activeId,
  ) {
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
        child: AnimatedContainer(
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
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
            boxShadow: widget.isSelected
                ? [
                    BoxShadow(
                      color: colorScheme.primary.withValues(alpha: 0.12),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : const <BoxShadow>[],
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
                            onPressed: widget.actionsEnabled
                                ? _toggleModelChipsExpanded
                                : null,
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
                          onPressed: widget.actionsEnabled && !widget.isFirst
                              ? widget.onMoveUp
                              : null,
                          tooltip: l10n.aiModelMoveUp,
                          icon: const Icon(Icons.arrow_upward_rounded),
                        ),
                        IconButton(
                          onPressed: widget.actionsEnabled && !widget.isLast
                              ? widget.onMoveDown
                              : null,
                          tooltip: l10n.aiModelMoveDown,
                          icon: const Icon(Icons.arrow_downward_rounded),
                        ),
                        IconButton(
                          onPressed: widget.actionsEnabled
                              ? widget.onEdit
                              : null,
                          tooltip: l10n.commonEdit,
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          onPressed: widget.actionsEnabled
                              ? widget.onDelete
                              : null,
                          tooltip: l10n.commonDelete,
                          icon: const Icon(Icons.delete_outline_rounded),
                        ),
                        IconButton(
                          onPressed: widget.actionsEnabled && !widget.isTesting
                              ? widget.onTest
                              : null,
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

/// 带弹性进退场动效的设置行显示/隐藏容器。
///
/// 用 [AnimatedSize]（高度弹性伸缩，easeOutBack 曲线）+ [AnimatedSwitcher]
/// （淡入淡出）组合，实现 Q 弹自然的条目显示/隐藏动效。
/// 自动遵守 [MediaQuery.disableAnimationsOf] 无动画设置。
class _AnimatedSettingReveal extends StatelessWidget {
  const _AnimatedSettingReveal({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return visible ? child : const SizedBox.shrink();
    }
    return ClipRect(
      child: AnimatedSize(
        duration: const Duration(milliseconds: 420),
        reverseDuration: const Duration(milliseconds: 260),
        curve: Curves.easeOutBack,
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 320),
          reverseDuration: const Duration(milliseconds: 200),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            return AnimatedBuilder(
              animation: animation,
              builder: (context, _) {
                final raw = animation.value.clamp(0.0, 1.0);
                final slideT = Curves.easeOutBack.transform(raw);
                final scaleT = Curves.easeOutCubic.transform(raw);
                return SlideTransition(
                  position: AlwaysStoppedAnimation<Offset>(
                    Offset(0, -0.06 * (1.0 - slideT)),
                  ),
                  child: FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: AlwaysStoppedAnimation<double>(
                        0.97 + 0.03 * scaleT,
                      ),
                      alignment: Alignment.topCenter,
                      child: child,
                    ),
                  ),
                );
              },
            );
          },
          child: visible
              ? KeyedSubtree(key: const ValueKey(true), child: child)
              : const SizedBox.shrink(key: ValueKey(false)),
        ),
      ),
    );
  }
}

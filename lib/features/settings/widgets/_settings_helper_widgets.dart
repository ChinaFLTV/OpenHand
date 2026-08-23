part of 'settings_view.dart';

const int _aiModelChipPreviewLimit = 8;
const double _aiModelSearchClearActionSize = 36;
const String _settingsZeroDurationLabel = '0s';
const double _aiProviderInfoChipMinHeight = 40;
const double _aiProviderInfoChipIconSize = 18;
const double _aiProviderInfoChipHorizontalPadding = 12;
const double _aiProviderInfoChipLabelPadding = 8;
const double _aiProviderInfoChipVerticalPadding = 10;
const double _aiProviderInfoChipLineHeight = 1.2;
const double _aiTtsDragHandleSize = 34;
const double _aiTtsCardActionSize = 40;
const double _aiCardActionEnabledAlpha = 0.74;
const double _aiCardActionDisabledAlpha = 0.42;
const double _aiTtsDragFeedbackMaxHeight = 240;
const double _settingsStandardFieldWidth = 360;
const String _translationSettingsTestText = 'Hello, OpenHand.';
const bool _settingsProviderCardDefaultExpanded = false;
const int _miniMaxDefaultSampleRate = 32000;
const int _miniMaxDefaultBitrate = 128000;
const int _miniMaxDefaultChannel = 1;
const List<AiTtsCatalogOption> _miniMaxSampleRateOptions = <AiTtsCatalogOption>[
  AiTtsCatalogOption('8000', '8 kHz'),
  AiTtsCatalogOption('16000', '16 kHz'),
  AiTtsCatalogOption('22050', '22.05 kHz'),
  AiTtsCatalogOption('24000', '24 kHz'),
  AiTtsCatalogOption('32000', '32 kHz'),
  AiTtsCatalogOption('44100', '44.1 kHz'),
];
const List<AiTtsCatalogOption> _miniMaxChannelOptions = <AiTtsCatalogOption>[
  AiTtsCatalogOption('1', 'Mono · 1'),
  AiTtsCatalogOption('2', 'Stereo · 2'),
];
const List<AiTtsCatalogOption> _miniMaxBitrateOptions = <AiTtsCatalogOption>[
  AiTtsCatalogOption('32000', '32 kbps'),
  AiTtsCatalogOption('64000', '64 kbps'),
  AiTtsCatalogOption('128000', '128 kbps'),
  AiTtsCatalogOption('256000', '256 kbps'),
];
const List<AiTtsCatalogOption> _miniMaxSubtitleTypeOptions =
    <AiTtsCatalogOption>[
      AiTtsCatalogOption('sentence', '句级时间戳', 'Sentence Timestamps'),
      AiTtsCatalogOption('word', '词级时间戳', 'Word Timestamps'),
      AiTtsCatalogOption(
        'word_streaming',
        '流式词级时间戳',
        'Streaming Word Timestamps',
      ),
    ];
const List<AiTtsCatalogOption> _miniMaxSoundEffectOptions =
    <AiTtsCatalogOption>[
      AiTtsCatalogOption('', '无音效', 'No Effect'),
      AiTtsCatalogOption('spacious_echo', '空旷回音', 'Spacious Echo'),
      AiTtsCatalogOption('auditorium_echo', '礼堂广播', 'Auditorium Echo'),
      AiTtsCatalogOption('lofi_telephone', '电话失真', 'Lo-fi Telephone'),
      AiTtsCatalogOption('robotic', '电音', 'Robotic'),
    ];

List<String> _filterAiModelIds(Iterable<String> modelIds, String query) {
  final normalizedQuery = query.trim().toLowerCase();
  final values = modelIds.toList(growable: false);
  if (normalizedQuery.isEmpty) return values;
  return values
      .where((modelId) => modelId.toLowerCase().contains(normalizedQuery))
      .toList(growable: false);
}

class _AiModelSearchField extends StatelessWidget {
  const _AiModelSearchField({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.onChanged,
    this.helperText,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search_rounded),
        hintText: openHandLocalizedText(
          context,
          zh: '搜索模型 ID',
          zhHant: '搜尋模型 ID',
          en: 'Search model IDs',
          fr: 'Rechercher un ID de modèle',
          de: 'Modell-ID suchen',
          ja: 'モデル ID を検索',
        ),
        helperText: helperText,
        suffixIconConstraints: const BoxConstraints(
          minWidth: 52,
          minHeight: 40,
        ),
        suffixIcon: controller.text.isEmpty
            ? null
            : Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: MicroPressFeedback(
                  scale: 0.92,
                  child: IconButton(
                    tooltip: openHandClearSearchLabel(context),
                    onPressed: () {
                      controller.clear();
                      onChanged('');
                      focusNode.requestFocus();
                    },
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      foregroundColor: colorScheme.onSurfaceVariant,
                      minimumSize: const Size.square(
                        _aiModelSearchClearActionSize,
                      ),
                      maximumSize: const Size.square(
                        _aiModelSearchClearActionSize,
                      ),
                      padding: EdgeInsets.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.clear_rounded, size: 20),
                  ),
                ),
              ),
        isDense: true,
      ),
      onChanged: onChanged,
    );
  }
}

class _AiModelSearchToggleButton extends StatelessWidget {
  const _AiModelSearchToggleButton({
    required this.visible,
    required this.enabled,
    required this.onPressed,
  });

  final bool visible;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return MicroPressFeedback(
      scale: 0.92,
      enabled: enabled,
      child: IconButton(
        onPressed: enabled ? onPressed : null,
        tooltip: visible
            ? openHandLocalizedText(
                context,
                zh: '关闭模型搜索',
                zhHant: '關閉模型搜尋',
                en: 'Close model search',
                fr: 'Fermer la recherche de modèles',
                de: 'Modellsuche schließen',
                ja: 'モデル検索を閉じる',
              )
            : openHandLocalizedText(
                context,
                zh: '搜索模型',
                zhHant: '搜尋模型',
                en: 'Search models',
                fr: 'Rechercher des modèles',
                de: 'Modelle suchen',
                ja: 'モデルを検索',
              ),
        icon: AnimatedSwitcher(
          duration: openHandMotionDuration(context, kOpenHandMotion180),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(scale: animation, child: child),
          ),
          child: Icon(
            visible ? Icons.search_off_rounded : Icons.search_rounded,
            key: ValueKey<bool>(visible),
          ),
        ),
      ),
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
              kOpenHandGap8,
              Text(
                description,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              kOpenHandGap18,
              ..._intersperse(children, kOpenHandGap18),
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
    final motionEnabled = _settingsMotionEnabled(context);
    final revealDuration = openHandMotionDuration(context, kOpenHandMotion420);
    final revealReverseDuration = openHandMotionDuration(
      context,
      kOpenHandMotion260,
    );
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleLarge),
        kOpenHandGap6,
        Text(
          description,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        kOpenHandGap16,
        if (motionEnabled)
          ClipRect(
            child: AnimatedSize(
              duration: revealDuration,
              reverseDuration: revealReverseDuration,
              curve: kOpenHandEntranceCurve,
              alignment: Alignment.topCenter,
              child: child,
            ),
          )
        else
          child,
      ],
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(kOpenHandRadius24),
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
                kOpenHandGap6,
                Text(
                  subtitle!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              kOpenHandGap14,
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
                    kOpenHandGap6,
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
            kOpenHandHGap20,
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
    required this.availableModels,
    required this.recentModelSelections,
  });

  final AiTtsSettings settings;
  final Future<bool> Function(AiTtsSettings settings) onChanged;
  final AiTtsPlaybackService playbackService;
  final List<AiModelConfig> availableModels;
  final List<RecentModelSelection> recentModelSelections;

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
          borderRadius: kOpenHandBorderRadius16,
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
                  title: openHandLocalizedText(
                    context,
                    zh: '朗读超时',
                    en: 'Read Timeout',
                  ),
                  subtitle: openHandLocalizedText(
                    context,
                    zh: '单次朗读或服务调用的最长等待秒数，防止无限等待。',
                    en: 'Maximum seconds for one read attempt.',
                  ),
                  control: _SettingsIntSlider(
                    value: settings.timeoutSeconds,
                    min: AiTtsSettings.minTimeoutSeconds,
                    max: AiTtsSettings.maxTimeoutSeconds,
                    step: 1,
                    suffix: 's',
                    onChanged: (value) =>
                        onChanged(settings.copyWith(timeoutSeconds: value)),
                  ),
                  controlMaxWidth: _settingsStandardFieldWidth,
                ),
                kOpenHandGap16,
                _ResponsiveSettingRow(
                  title: openHandLocalizedText(
                    context,
                    zh: '最大朗读字符',
                    en: 'Max Read Characters',
                  ),
                  subtitle: openHandLocalizedText(
                    context,
                    zh: '超出后自动截断，避免长消息占用朗读资源过久。',
                    en: 'Long messages are truncated to keep playback bounded.',
                  ),
                  control: _SettingsIntSlider(
                    value: settings.maxTextCharacters,
                    min: AiTtsSettings.minMaxTextCharacters,
                    max: AiTtsSettings.maxMaxTextCharacters,
                    step: 20,
                    onChanged: (value) =>
                        onChanged(settings.copyWith(maxTextCharacters: value)),
                  ),
                  controlMaxWidth: _settingsStandardFieldWidth,
                ),
                kOpenHandGap16,
                _AiTtsProviderDeck(
                  settings: settings,
                  onChanged: onChanged,
                  playbackService: playbackService,
                  availableModels: availableModels,
                  recentModelSelections: recentModelSelections,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AiTranslationSettingsPanel extends StatelessWidget {
  const _AiTranslationSettingsPanel({
    required this.settings,
    required this.onChanged,
    required this.availableModels,
    required this.recentModelSelections,
  });

  final AiTranslationSettings settings;
  final Future<bool> Function(AiTranslationSettings settings) onChanged;
  final List<AiModelConfig> availableModels;
  final List<RecentModelSelection> recentModelSelections;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 620),
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
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ResponsiveSettingRow(
                  title: openHandLocalizedText(
                    context,
                    zh: '待翻译语种',
                    en: 'Source Language',
                  ),
                  subtitle: openHandLocalizedText(
                    context,
                    zh: '默认自动检测。传统翻译接口不支持自动检测时会按服务能力兜底。',
                    en: 'Defaults to auto-detect. Providers fall back by capability.',
                  ),
                  control: _SettingsStringDropdown(
                    label: openHandLocalizedText(
                      context,
                      zh: '源语言',
                      en: 'Source',
                    ),
                    value: settings.sourceLanguage,
                    options: _translationLanguageDropdownOptions(
                      context,
                      AiTranslationProviderCatalogs.sourceLanguageOptions,
                    ),
                    onChanged: (value) =>
                        onChanged(settings.copyWith(sourceLanguage: value)),
                  ),
                  controlMaxWidth: _settingsStandardFieldWidth,
                ),
                kOpenHandGap16,
                _ResponsiveSettingRow(
                  title: openHandLocalizedText(
                    context,
                    zh: '目标语种',
                    en: 'Target Language',
                  ),
                  subtitle: openHandLocalizedText(
                    context,
                    zh: '消息卡片会翻译为该语言，原始消息不被改写。',
                    en: 'Message cards render into this language without mutating history.',
                  ),
                  control: _SettingsStringDropdown(
                    label: openHandLocalizedText(
                      context,
                      zh: '目标语言',
                      en: 'Target',
                    ),
                    value: settings.targetLanguage,
                    options: _translationLanguageDropdownOptions(
                      context,
                      AiTranslationProviderCatalogs.targetLanguageOptions,
                    ),
                    onChanged: (value) =>
                        onChanged(settings.copyWith(targetLanguage: value)),
                  ),
                  controlMaxWidth: _settingsStandardFieldWidth,
                ),
                kOpenHandGap16,
                _ResponsiveSettingRow(
                  title: openHandLocalizedText(
                    context,
                    zh: '翻译超时',
                    en: 'Translation Timeout',
                  ),
                  subtitle: openHandLocalizedText(
                    context,
                    zh: '单次翻译调用最长等待秒数，超时后按服务优先级回退。',
                    en: 'Maximum seconds per translation attempt before fallback.',
                  ),
                  control: _SettingsIntSlider(
                    value: settings.timeoutSeconds,
                    min: AiTranslationSettings.minTimeoutSeconds,
                    max: AiTranslationSettings.maxTimeoutSeconds,
                    step: 1,
                    suffix: 's',
                    onChanged: (value) =>
                        onChanged(settings.copyWith(timeoutSeconds: value)),
                  ),
                  controlMaxWidth: _settingsStandardFieldWidth,
                ),
                kOpenHandGap16,
                _ResponsiveSettingRow(
                  title: openHandLocalizedText(
                    context,
                    zh: '最大翻译字符',
                    en: 'Max Translation Characters',
                  ),
                  subtitle: openHandLocalizedText(
                    context,
                    zh: '长消息会被截断后翻译，避免接口长时间占用资源。',
                    en: 'Long messages are truncated to keep translation bounded.',
                  ),
                  control: _SettingsIntSlider(
                    value: settings.maxTextCharacters,
                    min: AiTranslationSettings.minMaxTextCharacters,
                    max: AiTranslationSettings.maxMaxTextCharacters,
                    step: 20,
                    onChanged: (value) =>
                        onChanged(settings.copyWith(maxTextCharacters: value)),
                  ),
                  controlMaxWidth: _settingsStandardFieldWidth,
                ),
                kOpenHandGap16,
                _AiTranslationProviderDeck(
                  settings: settings,
                  onChanged: onChanged,
                  availableModels: availableModels,
                  recentModelSelections: recentModelSelections,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AiTranslationProviderDeck extends StatefulWidget {
  const _AiTranslationProviderDeck({
    required this.settings,
    required this.onChanged,
    required this.availableModels,
    required this.recentModelSelections,
  });

  final AiTranslationSettings settings;
  final Future<bool> Function(AiTranslationSettings settings) onChanged;
  final List<AiModelConfig> availableModels;
  final List<RecentModelSelection> recentModelSelections;

  @override
  State<_AiTranslationProviderDeck> createState() =>
      _AiTranslationProviderDeckState();
}

class _AiTranslationProviderDeckState
    extends State<_AiTranslationProviderDeck> {
  AiTranslationProvider? _draggingProvider;
  int? _hoverInsertIndex;
  final Map<AiTranslationProvider, GlobalKey> _providerKeys =
      <AiTranslationProvider, GlobalKey>{};

  @override
  void didUpdateWidget(covariant _AiTranslationProviderDeck oldWidget) {
    super.didUpdateWidget(oldWidget);
    _providerKeys.removeWhere(
      (provider, _) => !widget.settings.providerPriority.contains(provider),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final providers = widget.settings.providerPriority;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          openHandLocalizedText(
            context,
            zh: '翻译服务优先级',
            en: 'Translation Priority',
          ),
          style: theme.textTheme.titleMedium,
        ),
        kOpenHandGap6,
        Text(
          openHandLocalizedText(
            context,
            zh: '拖动下方服务卡片调整优先级；不可用、缺少凭据或超时时自动回退。',
            en: 'Drag provider cards to set priority; unavailable services fall back.',
          ),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        kOpenHandGap10,
        DragTarget<AiTranslationProvider>(
          onWillAcceptWithDetails: (details) =>
              providers.contains(details.data),
          onMove: (details) => _updateHoverInsertIndex(details),
          onLeave: (_) => _clearHoverInsertIndex(),
          onAcceptWithDetails: (details) => _acceptProviderDrop(details),
          builder: (context, candidates, rejected) {
            return Column(
              children: [
                for (var index = 0; index < providers.length; index++) ...[
                  _AiProviderInsertionGuide(
                    visible:
                        _draggingProvider != null && _hoverInsertIndex == index,
                  ),
                  Padding(
                    key: _keyForProvider(providers[index]),
                    padding: EdgeInsets.only(
                      bottom: index == providers.length - 1 ? 0 : 12,
                    ),
                    child: _AiTranslationProviderCard(
                      settings: widget.settings,
                      provider: providers[index],
                      priorityIndex: index,
                      dragging: _draggingProvider == providers[index],
                      onDragStarted: () {
                        if (!mounted) return;
                        setState(() => _draggingProvider = providers[index]);
                      },
                      onDragEnded: (details) =>
                          _completeProviderDrag(providers[index], details),
                      onChanged: widget.onChanged,
                      availableModels: widget.availableModels,
                      recentModelSelections: widget.recentModelSelections,
                    ),
                  ),
                ],
                _AiProviderInsertionGuide(
                  visible:
                      _draggingProvider != null &&
                      _hoverInsertIndex == providers.length,
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  GlobalKey _keyForProvider(AiTranslationProvider provider) {
    return _providerKeys.putIfAbsent(provider, GlobalKey.new);
  }

  void _updateHoverInsertIndex(
    DragTargetDetails<AiTranslationProvider> details,
  ) {
    final insertIndex = _settingsProviderPriorityInsertIndex(
      widget.settings.providerPriority,
      details.data,
      details.offset,
      _providerKeys,
    );
    if (_hoverInsertIndex == insertIndex) return;
    setState(() => _hoverInsertIndex = insertIndex);
  }

  void _clearHoverInsertIndex() {
    if (_hoverInsertIndex == null) return;
    setState(() => _hoverInsertIndex = null);
  }

  void _acceptProviderDrop(DragTargetDetails<AiTranslationProvider> details) {
    final insertIndex = _settingsProviderPriorityInsertIndex(
      widget.settings.providerPriority,
      details.data,
      details.offset,
      _providerKeys,
    );
    if (mounted && _hoverInsertIndex != null) {
      setState(() => _hoverInsertIndex = null);
    }
    final next = _settingsReorderedProviderPriorityAt<AiTranslationProvider>(
      widget.settings.providerPriority,
      details.data,
      insertIndex,
    );
    if (next == null) return;
    widget.onChanged(widget.settings.copyWith(providerPriority: next));
  }

  void _completeProviderDrag(
    AiTranslationProvider provider,
    DraggableDetails details,
  ) {
    if (!mounted) return;
    final next = details.wasAccepted
        ? null
        : _settingsReorderedProviderPriorityAt<AiTranslationProvider>(
            widget.settings.providerPriority,
            provider,
            _settingsProviderPriorityInsertIndex(
              widget.settings.providerPriority,
              provider,
              details.offset,
              _providerKeys,
            ),
          );
    setState(() {
      _draggingProvider = null;
      _hoverInsertIndex = null;
    });
    if (next == null) return;
    widget.onChanged(widget.settings.copyWith(providerPriority: next));
  }
}

class _AiTranslationProviderCard extends StatefulWidget {
  const _AiTranslationProviderCard({
    required this.settings,
    required this.provider,
    required this.priorityIndex,
    required this.dragging,
    required this.onDragStarted,
    required this.onDragEnded,
    required this.onChanged,
    required this.availableModels,
    required this.recentModelSelections,
  });

  final AiTranslationSettings settings;
  final AiTranslationProvider provider;
  final int priorityIndex;
  final bool dragging;
  final VoidCallback onDragStarted;
  final void Function(DraggableDetails details) onDragEnded;
  final Future<bool> Function(AiTranslationSettings settings) onChanged;
  final List<AiModelConfig> availableModels;
  final List<RecentModelSelection> recentModelSelections;

  @override
  State<_AiTranslationProviderCard> createState() =>
      _AiTranslationProviderCardState();
}

class _AiTranslationProviderCardState
    extends State<_AiTranslationProviderCard> {
  bool _testing = false;
  bool _expanded = _settingsProviderCardDefaultExpanded;
  AiTranslationProviderSettings? _latestProviderSettings;

  AiTranslationProviderSettings get _effectiveProviderSettings =>
      (_latestProviderSettings ?? widget.settings.provider(widget.provider))
          .normalized();

  @override
  void didUpdateWidget(covariant _AiTranslationProviderCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.provider != widget.provider) {
      _latestProviderSettings = null;
      _expanded = _settingsProviderCardDefaultExpanded;
      return;
    }
    final wasEnabled = oldWidget.settings
        .provider(widget.provider)
        .normalized()
        .enabled;
    final isEnabled = widget.settings
        .provider(widget.provider)
        .normalized()
        .enabled;
    if (wasEnabled && !isEnabled) {
      _expanded = _settingsProviderCardDefaultExpanded;
    }
    final latest = _latestProviderSettings;
    if (latest == null) return;
    final persisted = widget.settings.provider(widget.provider).normalized();
    if (_settingsJsonEquals(latest.toJson(), persisted.toJson())) {
      _latestProviderSettings = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = widget.provider;
    final providerLabel = _translationProviderLabel(context, provider);
    final providerSettings = _effectiveProviderSettings;
    final readiness = providerSettings.enabled
        ? _translationProviderReadinessError(
            context,
            providerSettings,
            availableModels: widget.availableModels,
          )
        : null;
    final card = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: kOpenHandBorderRadius16,
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
              _AiProviderDragHandle<AiTranslationProvider>(
                data: provider,
                feedback: _AiTranslationProviderDragFeedbackCard(
                  label: providerLabel,
                  priorityIndex: widget.priorityIndex,
                  enabled: providerSettings.enabled,
                  width: _ttsDragFeedbackWidth(context),
                ),
                onDragStarted: widget.onDragStarted,
                onDragEnded: widget.onDragEnded,
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
                          providerLabel,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        _AiTtsStatusBadge(enabled: providerSettings.enabled),
                      ],
                    ),
                    kOpenHandGap5,
                    Text(
                      _translationProviderHint(context, provider),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              kOpenHandHGap8,
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.end,
                children: [
                  _AiProviderCardExpandButton(
                    expanded: _expanded,
                    enabled: providerSettings.enabled,
                    onPressed: _toggleExpanded,
                  ),
                  _AiTtsTestButton(
                    testing: _testing,
                    tooltip: openHandLocalizedText(
                      context,
                      zh: '测试文本翻译服务',
                      en: 'Test translation',
                    ),
                    onPressed: _testing ? null : _testProvider,
                  ),
                  _SettingsSwitch(
                    value: providerSettings.enabled,
                    onChanged: _setEnabled,
                  ),
                ],
              ),
            ],
          ),
          _AnimatedSettingReveal(
            visible: providerSettings.enabled && _expanded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (readiness != null) ...[
                  kOpenHandGap10,
                  Text(
                    readiness,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
                kOpenHandGap10,
                provider == AiTranslationProvider.ai
                    ? _buildAiModelSection(context, providerSettings)
                    : _buildProviderAccessSection(context, providerSettings),
              ],
            ),
          ),
        ],
      ),
    );
    return AnimatedOpacity(
      duration: openHandMotionDuration(context, kOpenHandMotion180),
      opacity: widget.dragging ? 0.58 : 1,
      child: card,
    );
  }

  void _toggleExpanded() {
    setState(() => _expanded = !_expanded);
    HapticFeedback.selectionClick();
  }

  Future<void> _setEnabled(bool value) {
    if (!value && _expanded) {
      setState(() => _expanded = _settingsProviderCardDefaultExpanded);
    }
    return _updateCurrent((current) => current.copyWith(enabled: value));
  }

  Future<void> _testProvider() async {
    if (_testing) return;
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;

    final current = _effectiveProviderSettings;
    final readinessError = _translationProviderReadinessError(
      context,
      current,
      availableModels: widget.availableModels,
    );
    if (readinessError != null) {
      _showSettingsTestErrorDialog(
        context: context,
        title: openHandLocalizedText(
          context,
          zh: '文本翻译测试无法开始',
          en: 'Translation Test Cannot Start',
        ),
        targetLabel: _translationProviderLabel(context, widget.provider),
        error: StateError(readinessError),
      );
      return;
    }

    setState(() => _testing = true);
    final service = AiTranslationService();
    try {
      final settingsController = context.read<SettingsController>();
      final result = await service.translate(
        text: _translationSettingsTestText,
        settings: _translationSettingsWithOnlyProvider(
          current.copyWith(enabled: true),
        ),
        availableModels: settingsController.aiModels,
        fallbackModel: settingsController.selectedAiModel,
      );
      if (!mounted) return;
      showOpenHandSuccessSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '文本翻译测试完成：${_compactSettingsPreview(result.text)}',
          en: 'Translation test completed: ${_compactSettingsPreview(result.text)}',
        ),
        maxLines: 2,
      );
    } catch (error, stack) {
      silentLog(
        'settings_translation',
        '测试 ${widget.provider.storageKey}',
        error,
        stack,
      );
      if (!mounted) return;
      _showSettingsTestErrorDialog(
        context: context,
        title: openHandLocalizedText(
          context,
          zh: '文本翻译测试失败',
          en: 'Translation Test Failed',
        ),
        targetLabel: _translationProviderLabel(context, widget.provider),
        error: error,
      );
    } finally {
      service.dispose();
      if (mounted) setState(() => _testing = false);
    }
  }

  Widget _buildAiModelSection(
    BuildContext context,
    AiTranslationProviderSettings providerSettings,
  ) {
    final theme = Theme.of(context);
    final selectedLabel = _selectedProviderModelLabel(
      configId: providerSettings.modelConfigId,
      modelId: providerSettings.modelId,
      models: widget.availableModels,
    );
    return _AiTtsProviderSection(
      title: _settingsHelperAiModelLabel(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FilledButton.tonalIcon(
            onPressed: widget.availableModels.isEmpty ? null : _pickAiModel,
            icon: const Icon(Icons.manage_search_rounded),
            label: Text(
              selectedLabel ??
                  openHandLocalizedText(
                    context,
                    zh: '选择翻译模型',
                    en: 'Select model',
                  ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          kOpenHandGap8,
          Text(
            selectedLabel == null
                ? openHandLocalizedText(
                    context,
                    zh: '未选择时会尝试使用当前会话/全局默认模型。',
                    en: 'Falls back to the current/global model when empty.',
                  )
                : openHandLocalizedText(
                    context,
                    zh: 'AI 翻译会复用该模型供应商的鉴权与接口配置。',
                    en: 'AI translation reuses this provider configuration.',
                  ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProviderAccessSection(
    BuildContext context,
    AiTranslationProviderSettings providerSettings,
  ) {
    final provider = widget.provider;
    return _AiTtsProviderSection(
      title: _settingsHelperAccessLabel(context),
      child: _AiTtsProviderFieldGrid(
        children: [
          _AiTtsProviderTextField(
            label: _settingsHelperEndpointLabel(context),
            value: providerSettings.endpoint,
            onSubmitted: (value) =>
                _updateCurrent((current) => current.copyWith(endpoint: value)),
          ),
          if (provider == AiTranslationProvider.baidu)
            _AiTtsProviderTextField(
              label: 'App ID',
              value: providerSettings.appId,
              onSubmitted: (value) =>
                  _updateCurrent((current) => current.copyWith(appId: value)),
            ),
          if (provider == AiTranslationProvider.doubao)
            _AiTtsProviderTextField(
              label: openHandLocalizedText(
                context,
                zh: 'App ID（旧版）',
                en: 'App ID',
              ),
              value: providerSettings.appId,
              onSubmitted: (value) =>
                  _updateCurrent((current) => current.copyWith(appId: value)),
            ),
          if (provider == AiTranslationProvider.youdao ||
              provider == AiTranslationProvider.google ||
              provider == AiTranslationProvider.bing ||
              provider == AiTranslationProvider.doubao)
            _AiTtsProviderTextField(
              label: _translationPrimaryCredentialLabel(provider),
              value: providerSettings.apiKey,
              obscure: true,
              onSubmitted: (value) =>
                  _updateCurrent((current) => current.copyWith(apiKey: value)),
            ),
          if (provider == AiTranslationProvider.baidu ||
              provider == AiTranslationProvider.youdao ||
              provider == AiTranslationProvider.doubao)
            _AiTtsProviderTextField(
              label: _translationSecondaryCredentialLabel(provider),
              value: providerSettings.apiSecret,
              obscure: true,
              onSubmitted: (value) => _updateCurrent(
                (current) => current.copyWith(apiSecret: value),
              ),
            ),
          if (provider == AiTranslationProvider.bing)
            _AiTtsProviderTextField(
              label: _settingsHelperRegionLabel(context),
              value: providerSettings.region,
              onSubmitted: (value) =>
                  _updateCurrent((current) => current.copyWith(region: value)),
            ),
          if (provider == AiTranslationProvider.apple) ...[
            _AiTtsProviderTextField(
              label: 'API Key',
              value: providerSettings.apiKey,
              obscure: true,
              onSubmitted: (value) =>
                  _updateCurrent((current) => current.copyWith(apiKey: value)),
            ),
            _AiTtsProviderTextField(
              label: 'Access Token',
              value: providerSettings.accessToken,
              obscure: true,
              onSubmitted: (value) => _updateCurrent(
                (current) => current.copyWith(accessToken: value),
              ),
            ),
          ],
          if (provider == AiTranslationProvider.doubao) ...[
            _AiTtsProviderTextField(
              label: 'Resource ID',
              value:
                  '${providerSettings.extra['resource_id'] ?? 'volc.speech.mt'}',
              onSubmitted: (value) => _updateExtra(
                'resource_id',
                value.isEmpty ? 'volc.speech.mt' : value,
              ),
            ),
            _AiTtsProviderTextField(
              label: openHandLocalizedText(
                context,
                zh: '术语 JSON',
                en: 'Corpus JSON',
              ),
              value: '${providerSettings.extra['corpus_json'] ?? ''}',
              onSubmitted: (value) => _updateExtra('corpus_json', value),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickAiModel() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final settingsController = context.read<SettingsController>();
    final latestModels = settingsController.aiModels;
    final current = _effectiveProviderSettings;
    final picked = await showModelSearchSelector(
      context: context,
      models: latestModels,
      selectedConfigId: current.modelConfigId,
      selectedModelId: current.modelId,
      recentSelections: widget.recentModelSelections,
    );
    if (!mounted || picked == null) return;
    await settingsController.addRecentModelSelection(picked.$1, picked.$2);
    await _updateCurrent(
      (current) =>
          current.copyWith(modelConfigId: picked.$1, modelId: picked.$2),
    );
  }

  Future<void> _update(AiTranslationProviderSettings next) async {
    _latestProviderSettings = next.normalized();
    if (mounted) setState(() {});
    await widget.onChanged(_settingsWithProvider(next));
  }

  Future<void> _updateCurrent(
    AiTranslationProviderSettings Function(
      AiTranslationProviderSettings current,
    )
    patch,
  ) {
    return _update(patch(_effectiveProviderSettings).normalized());
  }

  Future<void> _updateExtra(String key, Object? value) {
    final current = _effectiveProviderSettings;
    final extra = Map<String, Object?>.from(current.extra);
    extra[key] = value;
    return _update(current.copyWith(extra: extra).normalized());
  }

  AiTranslationSettings _settingsWithProvider(
    AiTranslationProviderSettings next,
  ) {
    final providers =
        Map<AiTranslationProvider, AiTranslationProviderSettings>.from(
          widget.settings.providers,
        );
    providers[widget.provider] = next.normalized();
    return widget.settings.copyWith(providers: providers);
  }

  AiTranslationSettings _translationSettingsWithOnlyProvider(
    AiTranslationProviderSettings next,
  ) {
    final providers = <AiTranslationProvider, AiTranslationProviderSettings>{
      for (final provider in AiTranslationProvider.values)
        provider: widget.settings
            .provider(provider)
            .copyWith(enabled: provider == widget.provider),
    };
    providers[widget.provider] = next.copyWith(enabled: true).normalized();
    return widget.settings.copyWith(
      enabled: true,
      providers: providers,
      providerPriority: <AiTranslationProvider>[widget.provider],
    );
  }
}

class _AiProviderDragHandle<T extends Object> extends StatefulWidget {
  const _AiProviderDragHandle({
    required this.data,
    required this.feedback,
    required this.onDragStarted,
    required this.onDragEnded,
  });

  final T data;
  final Widget feedback;
  final VoidCallback onDragStarted;
  final void Function(DraggableDetails details) onDragEnded;

  @override
  State<_AiProviderDragHandle<T>> createState() =>
      _AiProviderDragHandleState<T>();
}

class _AiProviderDragHandleState<T extends Object>
    extends State<_AiProviderDragHandle<T>> {
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final handle = _buildHandle(opacity: _dragging ? 0.42 : 1);
    return Draggable<T>(
      data: widget.data,
      maxSimultaneousDrags: 1,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      onDragStarted: _startDrag,
      onDragEnd: _finishDrag,
      feedback: Directionality(
        textDirection: Directionality.of(context),
        child: Theme(
          data: theme,
          child: Material(color: Colors.transparent, child: widget.feedback),
        ),
      ),
      childWhenDragging: _buildHandle(opacity: 0.42),
      child: handle,
    );
  }

  Widget _buildHandle({required double opacity}) {
    return _AiProviderDragHandleFrame(opacity: opacity);
  }

  void _startDrag() {
    if (_dragging) return;
    setState(() => _dragging = true);
    HapticFeedback.selectionClick();
    widget.onDragStarted();
  }

  void _finishDrag(DraggableDetails details) {
    if (!_dragging) return;
    if (mounted) {
      setState(() => _dragging = false);
    }
    widget.onDragEnded(details);
  }
}

class _AiTranslationProviderDragFeedbackCard extends StatelessWidget {
  const _AiTranslationProviderDragFeedbackCard({
    required this.label,
    required this.priorityIndex,
    required this.enabled,
    required this.width,
  });

  final String label;
  final int priorityIndex;
  final bool enabled;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: width,
        maxHeight: _aiTtsDragFeedbackMaxHeight,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: kOpenHandBorderRadius16,
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.28),
          ),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.shadow.withValues(alpha: 0.20),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.drag_indicator_rounded, size: 22),
              kOpenHandHGap10,
              _AiTtsPriorityBadge(index: priorityIndex),
              kOpenHandHGap8,
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              kOpenHandHGap8,
              _AiTtsStatusBadge(enabled: enabled),
            ],
          ),
        ),
      ),
    );
  }
}

class _AiTtsProviderDeck extends StatefulWidget {
  const _AiTtsProviderDeck({
    required this.settings,
    required this.onChanged,
    required this.playbackService,
    required this.availableModels,
    required this.recentModelSelections,
  });

  final AiTtsSettings settings;
  final Future<bool> Function(AiTtsSettings settings) onChanged;
  final AiTtsPlaybackService playbackService;
  final List<AiModelConfig> availableModels;
  final List<RecentModelSelection> recentModelSelections;

  @override
  State<_AiTtsProviderDeck> createState() => _AiTtsProviderDeckState();
}

class _AiTtsProviderDeckState extends State<_AiTtsProviderDeck> {
  AiTtsProvider? _draggingProvider;
  int? _hoverInsertIndex;
  final Map<AiTtsProvider, GlobalKey> _providerKeys =
      <AiTtsProvider, GlobalKey>{};

  @override
  void didUpdateWidget(covariant _AiTtsProviderDeck oldWidget) {
    super.didUpdateWidget(oldWidget);
    _providerKeys.removeWhere(
      (provider, _) => !widget.settings.providerPriority.contains(provider),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final providers = widget.settings.providerPriority;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          openHandLocalizedText(context, zh: 'TTS 服务优先级', en: 'TTS Priority'),
          style: theme.textTheme.titleMedium,
        ),
        kOpenHandGap6,
        Text(
          openHandLocalizedText(
            context,
            zh: '拖动下方服务卡片调整优先级；不可用或超时时自动回退。',
            en: 'Drag provider cards to set priority; unavailable services fall back.',
          ),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        kOpenHandGap10,
        DragTarget<AiTtsProvider>(
          onWillAcceptWithDetails: (details) =>
              providers.contains(details.data),
          onMove: (details) => _updateHoverInsertIndex(details),
          onLeave: (_) => _clearHoverInsertIndex(),
          onAcceptWithDetails: (details) => _acceptProviderDrop(details),
          builder: (context, candidates, rejected) {
            return Column(
              children: [
                for (var index = 0; index < providers.length; index++) ...[
                  _AiProviderInsertionGuide(
                    visible:
                        _draggingProvider != null && _hoverInsertIndex == index,
                  ),
                  Padding(
                    key: _keyForProvider(providers[index]),
                    padding: EdgeInsets.only(
                      bottom: index == providers.length - 1 ? 0 : 12,
                    ),
                    child: _AiTtsProviderCard(
                      settings: widget.settings,
                      provider: providers[index],
                      priorityIndex: index,
                      dragging: _draggingProvider == providers[index],
                      onDragStarted: () {
                        if (!mounted) return;
                        setState(() => _draggingProvider = providers[index]);
                      },
                      onDragEnded: (details) =>
                          _completeProviderDrag(providers[index], details),
                      onChanged: widget.onChanged,
                      playbackService: widget.playbackService,
                      availableModels: widget.availableModels,
                      recentModelSelections: widget.recentModelSelections,
                    ),
                  ),
                ],
                _AiProviderInsertionGuide(
                  visible:
                      _draggingProvider != null &&
                      _hoverInsertIndex == providers.length,
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  GlobalKey _keyForProvider(AiTtsProvider provider) {
    return _providerKeys.putIfAbsent(provider, GlobalKey.new);
  }

  void _updateHoverInsertIndex(DragTargetDetails<AiTtsProvider> details) {
    final insertIndex = _settingsProviderPriorityInsertIndex(
      widget.settings.providerPriority,
      details.data,
      details.offset,
      _providerKeys,
    );
    if (_hoverInsertIndex == insertIndex) return;
    setState(() => _hoverInsertIndex = insertIndex);
  }

  void _clearHoverInsertIndex() {
    if (_hoverInsertIndex == null) return;
    setState(() => _hoverInsertIndex = null);
  }

  void _acceptProviderDrop(DragTargetDetails<AiTtsProvider> details) {
    final insertIndex = _settingsProviderPriorityInsertIndex(
      widget.settings.providerPriority,
      details.data,
      details.offset,
      _providerKeys,
    );
    if (mounted && _hoverInsertIndex != null) {
      setState(() => _hoverInsertIndex = null);
    }
    final next = _settingsReorderedProviderPriorityAt<AiTtsProvider>(
      widget.settings.providerPriority,
      details.data,
      insertIndex,
    );
    if (next == null) return;
    widget.onChanged(widget.settings.copyWith(providerPriority: next));
  }

  void _completeProviderDrag(AiTtsProvider provider, DraggableDetails details) {
    if (!mounted) return;
    final next = details.wasAccepted
        ? null
        : _settingsReorderedProviderPriorityAt<AiTtsProvider>(
            widget.settings.providerPriority,
            provider,
            _settingsProviderPriorityInsertIndex(
              widget.settings.providerPriority,
              provider,
              details.offset,
              _providerKeys,
            ),
          );
    setState(() {
      _draggingProvider = null;
      _hoverInsertIndex = null;
    });
    if (next == null) return;
    widget.onChanged(widget.settings.copyWith(providerPriority: next));
  }
}

class _AiTtsProviderCard extends StatefulWidget {
  const _AiTtsProviderCard({
    required this.settings,
    required this.provider,
    required this.priorityIndex,
    required this.dragging,
    required this.onDragStarted,
    required this.onDragEnded,
    required this.onChanged,
    required this.playbackService,
    required this.availableModels,
    required this.recentModelSelections,
  });

  final AiTtsSettings settings;
  final AiTtsProvider provider;
  final int priorityIndex;
  final bool dragging;
  final VoidCallback onDragStarted;
  final void Function(DraggableDetails details) onDragEnded;
  final Future<bool> Function(AiTtsSettings settings) onChanged;
  final AiTtsPlaybackService playbackService;
  final List<AiModelConfig> availableModels;
  final List<RecentModelSelection> recentModelSelections;

  @override
  State<_AiTtsProviderCard> createState() => _AiTtsProviderCardState();
}

class _AiTtsProviderCardState extends State<_AiTtsProviderCard> {
  bool _testing = false;
  bool _loadingMiniMaxVoices = false;
  bool _expanded = _settingsProviderCardDefaultExpanded;
  AiTtsProviderSettings? _latestProviderSettings;
  String? _miniMaxVoiceModelKey;
  List<AiTtsCatalogOption> _miniMaxVoiceOptions = const <AiTtsCatalogOption>[];

  AiTtsProviderSettings get _effectiveProviderSettings =>
      _normalizeProviderSettingsForCurrentModel(
        (_latestProviderSettings ?? widget.settings.provider(widget.provider))
            .normalized(),
        widget.availableModels,
      );

  AiTtsProviderSettings _normalizeProviderSettingsForCurrentModel(
    AiTtsProviderSettings settings,
    List<AiModelConfig> models,
  ) {
    final normalized = settings.normalized();
    if (normalized.provider != AiTtsProvider.ai) return normalized;
    final model = _selectedAiTtsModel(settings: normalized, models: models);
    final protocol = model?.protocolType ?? AiProtocolType.openai;
    final modelId = (model?.modelId ?? normalized.modelId).trim();
    if (modelId.isEmpty) return normalized;

    final nextVoice = AiTtsProviderCatalogs.normalizeVoiceForAiModel(
      voice: normalized.voice,
      protocol: protocol,
      modelId: modelId,
    );
    final nextExtra = Map<String, Object?>.from(normalized.extra);
    if (AiTtsProviderCatalogs.usesStepFunSpeech(
      protocol: protocol,
      modelId: modelId,
    )) {
      nextExtra['format'] =
          AiTtsProviderCatalogs.normalizeStepFunResponseFormat(
            nextExtra['format'],
          );
    }
    return normalized
        .copyWith(
          voice: nextVoice,
          speed: _aiTtsNumberRangeForModel(
            protocol: protocol,
            modelId: modelId,
            kind: _TtsNumberKind.speed,
          ).snap(normalized.speed),
          volume: _aiTtsNumberRangeForModel(
            protocol: protocol,
            modelId: modelId,
            kind: _TtsNumberKind.volume,
          ).snap(normalized.volume),
          pitch: _aiTtsNumberRangeForModel(
            protocol: protocol,
            modelId: modelId,
            kind: _TtsNumberKind.pitch,
          ).snap(normalized.pitch),
          extra: nextExtra,
        )
        .normalized();
  }

  @override
  void didUpdateWidget(covariant _AiTtsProviderCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.provider != widget.provider) {
      _latestProviderSettings = null;
      _expanded = _settingsProviderCardDefaultExpanded;
      return;
    }
    final wasEnabled = oldWidget.settings
        .provider(widget.provider)
        .normalized()
        .enabled;
    final isEnabled = widget.settings
        .provider(widget.provider)
        .normalized()
        .enabled;
    if (wasEnabled && !isEnabled) {
      _expanded = _settingsProviderCardDefaultExpanded;
    }
    final latest = _latestProviderSettings;
    if (latest == null) return;
    final persisted = widget.settings.provider(widget.provider).normalized();
    if (_settingsJsonEquals(latest.toJson(), persisted.toJson())) {
      _latestProviderSettings = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = widget.provider;
    final providerLabel = _ttsProviderLabel(context, provider);
    final providerSettings = _effectiveProviderSettings;
    final catalog = AiTtsProviderCatalogs.of(provider);
    final card = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: kOpenHandBorderRadius16,
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
              _AiProviderDragHandle<AiTtsProvider>(
                data: provider,
                feedback: _AiTtsProviderDragFeedbackCard(
                  priorityIndex: widget.priorityIndex,
                  label: providerLabel,
                  enabled: providerSettings.enabled,
                  width: _ttsDragFeedbackWidth(context),
                ),
                onDragStarted: widget.onDragStarted,
                onDragEnded: widget.onDragEnded,
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
                          providerLabel,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        _AiTtsStatusBadge(enabled: providerSettings.enabled),
                      ],
                    ),
                    kOpenHandGap5,
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
              kOpenHandHGap8,
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.end,
                children: [
                  _AiProviderCardExpandButton(
                    expanded: _expanded,
                    enabled: providerSettings.enabled,
                    onPressed: _toggleExpanded,
                  ),
                  _AiTtsTestButton(
                    testing: _testing,
                    onPressed: _testing ? null : _testProvider,
                  ),
                  _SettingsSwitch(
                    value: providerSettings.enabled,
                    onChanged: _setEnabled,
                  ),
                ],
              ),
            ],
          ),
          _AnimatedSettingReveal(
            visible: providerSettings.enabled && _expanded,
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: provider == AiTtsProvider.ai
                  ? _buildAiModelSection(context, providerSettings)
                  : _buildNativeProviderSections(
                      context,
                      provider,
                      providerSettings,
                      catalog,
                    ),
            ),
          ),
        ],
      ),
    );
    return AnimatedOpacity(
      duration: openHandMotionDuration(context, kOpenHandMotion180),
      opacity: widget.dragging ? 0.58 : 1,
      child: card,
    );
  }

  void _toggleExpanded() {
    setState(() => _expanded = !_expanded);
    HapticFeedback.selectionClick();
  }

  Future<void> _setEnabled(bool value) {
    if (!value && _expanded) {
      setState(() => _expanded = _settingsProviderCardDefaultExpanded);
    }
    return _updateCurrent((current) => current.copyWith(enabled: value));
  }

  Widget _buildAiModelSection(
    BuildContext context,
    AiTtsProviderSettings providerSettings,
  ) {
    final theme = Theme.of(context);
    final model = _selectedAiTtsModel(
      settings: providerSettings,
      models: widget.availableModels,
    );
    final modelProtocol = model?.protocolType ?? AiProtocolType.openai;
    final modelId = (model?.modelId ?? providerSettings.modelId).trim();
    final voiceOptions = AiTtsProviderCatalogs.voiceOptionsForAiModel(
      protocol: modelProtocol,
      modelId: modelId,
    );
    final usesMiniMaxSpeech = AiTtsProviderCatalogs.usesMiniMaxSpeech(
      protocol: modelProtocol,
      modelId: modelId,
    );
    final usesMiniMaxNativeSpeech =
        modelProtocol == AiProtocolType.minimax && usesMiniMaxSpeech;
    final modelKey = model == null ? null : '${model.id}|${model.modelId}';
    final effectiveVoiceOptions =
        _settingsUniqueTtsOptions(<AiTtsCatalogOption>[
          ...voiceOptions,
          if (modelKey == _miniMaxVoiceModelKey) ..._miniMaxVoiceOptions,
        ]);
    final formatOptions = AiTtsProviderCatalogs.formatOptionsForAiModel(
      protocol: modelProtocol,
      modelId: modelId,
    );
    final usesStepFunSpeech = AiTtsProviderCatalogs.usesStepFunSpeech(
      protocol: modelProtocol,
      modelId: modelId,
    );
    final formatValue = usesStepFunSpeech
        ? AiTtsProviderCatalogs.normalizeStepFunResponseFormat(
            providerSettings.extra['format'],
          )
        : '${providerSettings.extra['format'] ?? 'mp3'}';
    final miniMaxVoiceModify = providerSettings.extra['voice_modify'] is Map
        ? stringKeyedMapFromValue(providerSettings.extra['voice_modify'])
        : const <String, Object?>{};
    final selectedLabel = _selectedProviderModelLabel(
      configId: providerSettings.modelConfigId,
      modelId: providerSettings.modelId,
      models: widget.availableModels,
    );
    final hasAudioModels = _ttsAudioGenerationModels(
      widget.availableModels,
    ).isNotEmpty;
    return _AiTtsProviderSection(
      title: _settingsHelperAiModelLabel(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: hasAudioModels ? _pickAiModel : null,
                icon: const Icon(Icons.manage_search_rounded),
                label: Text(
                  selectedLabel ??
                      openHandLocalizedText(
                        context,
                        zh: '选择语音模型',
                        en: 'Select model',
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (usesMiniMaxNativeSpeech && model != null)
                OutlinedButton.icon(
                  onPressed: _loadingMiniMaxVoices
                      ? null
                      : () => _loadMiniMaxVoices(model),
                  icon: AnimatedSwitcher(
                    duration: openHandMotionDuration(
                      context,
                      kOpenHandMotion220,
                    ),
                    child: _loadingMiniMaxVoices
                        ? const SizedBox.square(
                            key: ValueKey<String>('loading'),
                            dimension: 17,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(
                            Icons.sync_rounded,
                            key: ValueKey<String>('idle'),
                          ),
                  ),
                  label: Text(
                    openHandLocalizedText(
                      context,
                      zh: '同步 MiniMax 音色',
                      en: 'Sync MiniMax voices',
                    ),
                  ),
                ),
            ],
          ),
          kOpenHandGap8,
          Text(
            selectedLabel == null
                ? openHandLocalizedText(
                    context,
                    zh: '仅展示已标记为多模态且支持音频生成的模型。',
                    en: 'Only multimodal audio-generation models are listed.',
                  )
                : openHandLocalizedText(
                    context,
                    zh: 'AI 语音会复用该模型供应商的鉴权与接口配置。',
                    en: 'AI speech reuses this provider configuration.',
                  ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          kOpenHandGap12,
          _AiTtsProviderFieldGrid(
            children: [
              _AiTtsDropdown(
                label: openHandVoiceLabel(context),
                value: providerSettings.voice,
                options: effectiveVoiceOptions,
                onChanged: (value) => _updateCurrent((current) {
                  return current.copyWith(voice: value);
                }),
              ),
              _AiTtsDropdown(
                label: _settingsHelperFormatLabel(context),
                value: formatValue,
                options: formatOptions,
                onChanged: (value) => _updateExtra('format', value),
              ),
              _AiTtsProviderNumberField(
                label: openHandSpeedLabel(context),
                value: providerSettings.speed,
                range: _aiTtsNumberRangeForModel(
                  protocol: modelProtocol,
                  modelId: modelId,
                  kind: _TtsNumberKind.speed,
                ),
                onChanged: (value) => _updateCurrent((current) {
                  return current.copyWith(speed: value);
                }),
              ),
              _AiTtsProviderNumberField(
                label: openHandVolumeLabel(context),
                value: providerSettings.volume,
                range: _aiTtsNumberRangeForModel(
                  protocol: modelProtocol,
                  modelId: modelId,
                  kind: _TtsNumberKind.volume,
                ),
                onChanged: (value) => _updateCurrent((current) {
                  return current.copyWith(volume: value);
                }),
              ),
              _AiTtsProviderNumberField(
                label: _settingsHelperPitchLabel(context),
                value: providerSettings.pitch,
                range: _aiTtsNumberRangeForModel(
                  protocol: modelProtocol,
                  modelId: modelId,
                  kind: _TtsNumberKind.pitch,
                ),
                onChanged: (value) => _updateCurrent((current) {
                  return current.copyWith(pitch: value);
                }),
              ),
              if (usesMiniMaxNativeSpeech) ...[
                _AiTtsDropdown(
                  label: openHandLocalizedText(
                    context,
                    zh: '语言增强',
                    en: 'Language Boost',
                  ),
                  value:
                      '${providerSettings.extra['language_boost'] ?? 'auto'}',
                  options: AiTtsProviderCatalogs.miniMaxLanguageOptions,
                  onChanged: (value) => _updateExtra('language_boost', value),
                ),
                _AiTtsDropdown(
                  label: openHandLocalizedText(
                    context,
                    zh: '情绪',
                    en: 'Emotion',
                  ),
                  value: '${providerSettings.extra['emotion'] ?? ''}',
                  options: AiTtsProviderCatalogs.miniMaxEmotionOptions,
                  onChanged: (value) => _updateExtra('emotion', value),
                ),
                _AiTtsDropdown(
                  label: openHandLocalizedText(
                    context,
                    zh: '采样率',
                    en: 'Sample Rate',
                  ),
                  value:
                      '${providerSettings.extra['sample_rate'] ?? _miniMaxDefaultSampleRate}',
                  options: _miniMaxSampleRateOptions,
                  onChanged: (value) => _updateExtra(
                    'sample_rate',
                    intFromValue(value, fallback: _miniMaxDefaultSampleRate),
                  ),
                ),
                _AiTtsDropdown(
                  label: openHandLocalizedText(
                    context,
                    zh: '比特率',
                    en: 'Bitrate',
                  ),
                  value:
                      '${providerSettings.extra['bit_rate'] ?? _miniMaxDefaultBitrate}',
                  options: _miniMaxBitrateOptions,
                  onChanged: (value) => _updateExtra(
                    'bit_rate',
                    intFromValue(value, fallback: _miniMaxDefaultBitrate),
                  ),
                ),
                _AiTtsDropdown(
                  label: openHandLocalizedText(
                    context,
                    zh: '声道',
                    en: 'Channels',
                  ),
                  value:
                      '${providerSettings.extra['channel'] ?? _miniMaxDefaultChannel}',
                  options: _miniMaxChannelOptions,
                  onChanged: (value) => _updateExtra(
                    'channel',
                    intFromValue(value, fallback: _miniMaxDefaultChannel),
                  ),
                ),
                _AiTtsToggleField(
                  label: openHandLocalizedText(
                    context,
                    zh: '文本规范化',
                    en: 'Text Normalization',
                  ),
                  value:
                      optionalBoolFromValue(
                        providerSettings.extra['text_normalization'],
                      ) ??
                      false,
                  onChanged: (value) =>
                      _updateExtra('text_normalization', value),
                ),
                _AiTtsToggleField(
                  label: openHandLocalizedText(
                    context,
                    zh: '朗读 LaTeX',
                    en: 'Read LaTeX',
                  ),
                  value:
                      optionalBoolFromValue(
                        providerSettings.extra['latex_read'],
                      ) ??
                      false,
                  onChanged: (value) => _updateExtra('latex_read', value),
                ),
                _AiTtsToggleField(
                  label: openHandLocalizedText(
                    context,
                    zh: '生成字幕',
                    en: 'Generate Subtitles',
                  ),
                  value:
                      optionalBoolFromValue(
                        providerSettings.extra['subtitle_enable'],
                      ) ??
                      false,
                  onChanged: (value) => _updateExtra('subtitle_enable', value),
                ),
                if (optionalBoolFromValue(
                      providerSettings.extra['subtitle_enable'],
                    ) ==
                    true)
                  _AiTtsDropdown(
                    label: openHandLocalizedText(
                      context,
                      zh: '字幕粒度',
                      en: 'Subtitle Detail',
                    ),
                    value:
                        '${providerSettings.extra['subtitle_type'] ?? 'sentence'}',
                    options: _miniMaxSubtitleTypeOptions,
                    onChanged: (value) => _updateExtra('subtitle_type', value),
                  ),
                _AiTtsToggleField(
                  label: openHandLocalizedText(
                    context,
                    zh: '恒定比特率（流式 MP3）',
                    en: 'Constant Bitrate (Streaming MP3)',
                  ),
                  value:
                      optionalBoolFromValue(
                        providerSettings.extra['force_cbr'],
                      ) ??
                      false,
                  onChanged: (value) => _updateExtra('force_cbr', value),
                ),
                _AiTtsProviderTextField(
                  label: openHandLocalizedText(
                    context,
                    zh: '自定义发音（使用 ; 分隔）',
                    en: 'Pronunciations (separate with ;)',
                  ),
                  value: stringListFromListValue(
                    providerSettings.extra['pronunciation_tone'],
                  ).join('; '),
                  maxLines: 2,
                  onSubmitted: (value) => _updateExtra(
                    'pronunciation_tone',
                    _miniMaxDelimitedValues(value, separator: ';'),
                  ),
                ),
                _AiTtsProviderTextField(
                  label: openHandLocalizedText(
                    context,
                    zh: '混合音色（voice_id:权重，最多 4 个）',
                    en: 'Voice Mix (voice_id:weight, max 4)',
                  ),
                  value: _miniMaxTimbreWeightsText(
                    providerSettings.extra['timbre_weights'],
                  ),
                  maxLines: 2,
                  onSubmitted: (value) =>
                      unawaited(_updateMiniMaxTimbreWeights(value)),
                ),
                _AiTtsProviderNumberField(
                  label: openHandLocalizedText(
                    context,
                    zh: '效果器 · 音高',
                    en: 'Effect · Pitch',
                  ),
                  value:
                      optionalDoubleFromValue(miniMaxVoiceModify['pitch']) ?? 0,
                  range: const _TtsNumberRange(-100, 100),
                  onChanged: (value) =>
                      _updateMiniMaxVoiceModify('pitch', value.round()),
                ),
                _AiTtsProviderNumberField(
                  label: openHandLocalizedText(
                    context,
                    zh: '效果器 · 强度',
                    en: 'Effect · Intensity',
                  ),
                  value:
                      optionalDoubleFromValue(
                        miniMaxVoiceModify['intensity'],
                      ) ??
                      0,
                  range: const _TtsNumberRange(-100, 100),
                  onChanged: (value) =>
                      _updateMiniMaxVoiceModify('intensity', value.round()),
                ),
                _AiTtsProviderNumberField(
                  label: openHandLocalizedText(
                    context,
                    zh: '效果器 · 音色',
                    en: 'Effect · Timbre',
                  ),
                  value:
                      optionalDoubleFromValue(miniMaxVoiceModify['timbre']) ??
                      0,
                  range: const _TtsNumberRange(-100, 100),
                  onChanged: (value) =>
                      _updateMiniMaxVoiceModify('timbre', value.round()),
                ),
                _AiTtsDropdown(
                  label: openHandLocalizedText(
                    context,
                    zh: '效果器 · 场景',
                    en: 'Effect · Scene',
                  ),
                  value: '${miniMaxVoiceModify['sound_effects'] ?? ''}',
                  options: _miniMaxSoundEffectOptions,
                  onChanged: (value) =>
                      _updateMiniMaxVoiceModify('sound_effects', value),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _loadMiniMaxVoices(AiModelConfig model) async {
    if (_loadingMiniMaxVoices) return;
    setState(() => _loadingMiniMaxVoices = true);
    final service = AiMiniMaxVoiceService();
    try {
      final payload = await service.loadVoices(model: model);
      final options = _miniMaxVoiceOptionsFromPayload(payload);
      if (options.isEmpty) {
        throw StateError('MiniMax returned no available voices.');
      }
      if (!mounted) return;
      setState(() {
        _miniMaxVoiceModelKey = '${model.id}|${model.modelId}';
        _miniMaxVoiceOptions = options;
      });
      showOpenHandSuccessSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '已同步 ${options.length} 个 MiniMax 音色',
          en: 'Synced ${options.length} MiniMax voices',
        ),
      );
    } catch (error, stack) {
      silentLog('settings_tts', '同步 MiniMax 音色', error, stack);
      if (!mounted) return;
      _showSettingsTestErrorDialog(
        context: context,
        title: openHandLocalizedText(
          context,
          zh: 'MiniMax 音色同步失败',
          en: 'MiniMax Voice Sync Failed',
        ),
        targetLabel: 'MiniMax Voice API',
        error: error,
      );
    } finally {
      service.dispose();
      if (mounted) setState(() => _loadingMiniMaxVoices = false);
    }
  }

  Widget _buildNativeProviderSections(
    BuildContext context,
    AiTtsProvider provider,
    AiTtsProviderSettings providerSettings,
    AiTtsProviderCatalog catalog,
  ) {
    final mimoModel = '${providerSettings.extra['model'] ?? 'mimo-v2.5-tts'}';
    final usesMimoPresetVoice =
        provider != AiTtsProvider.mimo || mimoModel == 'mimo-v2.5-tts';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _AiTtsProviderSection(
          title: openHandLocalizedText(context, zh: '声音参数', en: 'Voice'),
          child: _AiTtsProviderFieldGrid(
            children: [
              if (usesMimoPresetVoice)
                _AiTtsDropdown(
                  label: openHandVoiceLabel(context),
                  value: providerSettings.voice,
                  options: catalog.voiceOptions,
                  onChanged: (value) => _updateCurrent((current) {
                    return current.copyWith(voice: value);
                  }),
                ),
              _AiTtsDropdown(
                label: openHandLocalizedText(context, zh: '语言', en: 'Language'),
                value: providerSettings.language,
                options: catalog.languageOptions,
                onChanged: (value) => _updateCurrent((current) {
                  return current.copyWith(language: value);
                }),
              ),
              if (provider != AiTtsProvider.mimo)
                _AiTtsProviderNumberField(
                  label: openHandSpeedLabel(context),
                  value: providerSettings.speed,
                  range: _ttsNumberRange(provider, _TtsNumberKind.speed),
                  onChanged: (value) => _updateCurrent((current) {
                    return current.copyWith(speed: value);
                  }),
                ),
              _AiTtsProviderNumberField(
                label: openHandVolumeLabel(context),
                value: providerSettings.volume,
                range: _ttsNumberRange(provider, _TtsNumberKind.volume),
                onChanged: (value) => _updateCurrent((current) {
                  return current.copyWith(volume: value);
                }),
              ),
              if (provider != AiTtsProvider.mimo)
                _AiTtsProviderNumberField(
                  label: _settingsHelperPitchLabel(context),
                  value: providerSettings.pitch,
                  range: _ttsNumberRange(provider, _TtsNumberKind.pitch),
                  onChanged: (value) => _updateCurrent((current) {
                    return current.copyWith(pitch: value);
                  }),
                ),
            ],
          ),
        ),
        if (_providerNeedsEndpoint(provider) ||
            _providerNeedsCredentials(provider)) ...[
          kOpenHandGap12,
          _AiTtsProviderSection(
            title: _settingsHelperAccessLabel(context),
            child: _AiTtsProviderFieldGrid(
              children: [
                if (_providerNeedsEndpoint(provider))
                  _AiTtsProviderTextField(
                    label: _settingsHelperEndpointLabel(context),
                    value: providerSettings.endpoint,
                    onSubmitted: (value) => _updateCurrent((current) {
                      return current.copyWith(endpoint: value);
                    }),
                  ),
                if (_needsAppIdCredential(provider))
                  _AiTtsProviderTextField(
                    label: 'App ID',
                    value: providerSettings.appId,
                    onSubmitted: (value) => _updateCurrent((current) {
                      return current.copyWith(appId: value);
                    }),
                  ),
                if (_providerNeedsCredentials(provider))
                  _AiTtsProviderTextField(
                    label: _primaryCredentialLabel(provider),
                    value: providerSettings.apiKey,
                    obscure: true,
                    onSubmitted: (value) => _updateCurrent((current) {
                      return current.copyWith(apiKey: value);
                    }),
                  ),
                if (_needsSecondaryCredential(provider))
                  _AiTtsProviderTextField(
                    label: _secondaryCredentialLabel(provider),
                    value: providerSettings.apiSecret,
                    obscure: true,
                    onSubmitted: (value) => _updateCurrent((current) {
                      return current.copyWith(apiSecret: value);
                    }),
                  ),
                if (provider == AiTtsProvider.baidu)
                  _AiTtsProviderTextField(
                    label: 'Access Token',
                    value: providerSettings.accessToken,
                    obscure: true,
                    onSubmitted: (value) => _updateCurrent((current) {
                      return current.copyWith(accessToken: value);
                    }),
                  ),
                if (provider == AiTtsProvider.bing)
                  _AiTtsProviderTextField(
                    label: _settingsHelperRegionLabel(context),
                    value: providerSettings.region,
                    onSubmitted: (value) => _updateCurrent((current) {
                      return current.copyWith(region: value);
                    }),
                  ),
              ],
            ),
          ),
        ],
        if (provider == AiTtsProvider.doubao) ...[
          kOpenHandGap12,
          _AiTtsProviderSection(
            title: openHandLocalizedText(context, zh: '豆包参数', en: 'Doubao'),
            child: _AiTtsProviderFieldGrid(
              children: [
                _AiTtsDropdown(
                  label: 'Resource ID',
                  value:
                      '${providerSettings.extra['resource_id'] ?? 'seed-tts-2.0'}',
                  options: catalog.resourceIdOptions,
                  onChanged: (value) => _updateExtra('resource_id', value),
                ),
                _AiTtsDropdown(
                  label: openHandModelLabel(context),
                  value:
                      '${providerSettings.extra['model'] ?? 'seed-tts-2.0-standard'}',
                  options: catalog.modelOptions,
                  onChanged: (value) => _updateExtra('model', value),
                ),
                _AiTtsDropdown(
                  label: _settingsHelperFormatLabel(context),
                  value: '${providerSettings.extra['format'] ?? 'mp3'}',
                  options: catalog.formatOptions,
                  onChanged: (value) => _updateExtra('format', value),
                ),
              ],
            ),
          ),
        ] else if (provider == AiTtsProvider.mimo) ...[
          kOpenHandGap12,
          _AiTtsProviderSection(
            title: 'Mimo TTS',
            child: _AiTtsProviderFieldGrid(
              children: [
                _AiTtsDropdown(
                  label: openHandModelLabel(context),
                  value:
                      '${providerSettings.extra['model'] ?? 'mimo-v2.5-tts'}',
                  options: catalog.modelOptions,
                  onChanged: (value) => _updateExtra('model', value),
                ),
                _AiTtsDropdown(
                  label: _settingsHelperFormatLabel(context),
                  value:
                      '${providerSettings.extra['format'] ?? aiMimoDefaultAudioFormat}',
                  options: catalog.formatOptions,
                  onChanged: (value) => _updateExtra('format', value),
                ),
                _AiTtsProviderTextField(
                  label: openHandLocalizedText(
                    context,
                    zh: '风格提示',
                    en: 'Style Prompt',
                  ),
                  value:
                      '${providerSettings.extra['style_prompt'] ?? '自然清晰，语速适中，语气友好。'}',
                  onSubmitted: (value) => _updateExtra('style_prompt', value),
                ),
                if ('${providerSettings.extra['model']}' ==
                    'mimo-v2.5-tts-voicedesign')
                  _AiTtsToggleField(
                    label: openHandLocalizedText(
                      context,
                      zh: '优化文本预览',
                      en: 'Optimize Text Preview',
                    ),
                    value: boolFromValue(
                      providerSettings.extra['optimize_text_preview'],
                    ),
                    onChanged: (value) =>
                        _updateExtra('optimize_text_preview', value),
                  ),
                if ('${providerSettings.extra['model']}' ==
                    'mimo-v2.5-tts-voiceclone')
                  _AiTtsProviderTextField(
                    label: _settingsHelperCloneSamplePathLabel(context),
                    value:
                        '${providerSettings.extra['voice_sample_path'] ?? ''}',
                    onSubmitted: (value) =>
                        _updateExtra('voice_sample_path', value),
                  ),
              ],
            ),
          ),
        ] else if (provider == AiTtsProvider.xfyun) ...[
          kOpenHandGap12,
          _AiTtsProviderSection(
            title: _settingsHelperAudioLabel(context),
            child: _AiTtsProviderFieldGrid(
              children: [
                _AiTtsDropdown(
                  label: _settingsHelperFormatLabel(context),
                  value: '${providerSettings.extra['aue'] ?? 'lame'}',
                  options: catalog.formatOptions,
                  onChanged: (value) => _updateExtra('aue', value),
                ),
              ],
            ),
          ),
        ] else if (provider == AiTtsProvider.google ||
            provider == AiTtsProvider.bing) ...[
          kOpenHandGap12,
          _AiTtsProviderSection(
            title: _settingsHelperAudioLabel(context),
            child: _AiTtsProviderFieldGrid(
              children: [
                _AiTtsDropdown(
                  label: _settingsHelperFormatLabel(context),
                  value:
                      '${providerSettings.extra[_audioEncodingExtraKey(provider)] ?? _defaultAudioEncoding(provider)}',
                  options: catalog.formatOptions,
                  onChanged: (value) =>
                      _updateExtra(_audioEncodingExtraKey(provider), value),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _testProvider() async {
    if (_testing) return;
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;
    final settingsController = context.read<SettingsController>();
    final fallbackModel = _ttsFallbackAudioModel(settingsController);
    final readinessError = _ttsProviderReadinessError(
      context,
      _effectiveProviderSettings,
      widget.availableModels,
      fallbackModel: fallbackModel,
    );
    if (readinessError != null) {
      _showSettingsTestErrorDialog(
        context: context,
        title: openHandLocalizedText(
          context,
          zh: 'TTS 测试无法开始',
          en: 'TTS Test Cannot Start',
        ),
        targetLabel: _ttsProviderLabel(context, widget.provider),
        error: StateError(readinessError),
      );
      return;
    }
    setState(() => _testing = true);
    try {
      final completed = await widget.playbackService.testProvider(
        settings: _settingsWithProvider(
          _effectiveProviderSettings,
        ).copyWith(enabled: true),
        provider: widget.provider,
        availableModels: widget.availableModels,
        fallbackModel: fallbackModel,
      );
      if (!mounted || !completed) return;
      showOpenHandSuccessSnack(
        context,
        openHandLocalizedText(context, zh: 'TTS 测试播放完成', en: 'TTS test played'),
      );
    } catch (error, stack) {
      if (!isAiTtsConfigurationError(error)) {
        silentLog(
          'settings_tts',
          '测试 ${widget.provider.storageKey}',
          error,
          stack,
        );
      }
      if (!mounted) return;
      _showSettingsTestErrorDialog(
        context: context,
        title: openHandLocalizedText(
          context,
          zh: 'TTS 测试失败',
          en: 'TTS Test Failed',
        ),
        targetLabel: _ttsProviderLabel(context, widget.provider),
        error: error,
      );
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _update(AiTtsProviderSettings next) async {
    _latestProviderSettings = next.normalized();
    if (mounted) setState(() {});
    await widget.onChanged(_settingsWithProvider(next));
  }

  Future<void> _updateCurrent(
    AiTtsProviderSettings Function(AiTtsProviderSettings current) patch,
  ) {
    return _update(patch(_effectiveProviderSettings));
  }

  AiTtsSettings _settingsWithProvider(AiTtsProviderSettings next) {
    final providers = Map<AiTtsProvider, AiTtsProviderSettings>.from(
      widget.settings.providers,
    );
    providers[widget.provider] = next.normalized();
    return widget.settings.copyWith(providers: providers);
  }

  Future<void> _updateExtra(String key, Object? value) async {
    final current = _effectiveProviderSettings;
    final extra = Map<String, Object?>.from(current.extra);
    extra[key] = value;
    await _update(current.copyWith(extra: extra));
  }

  Future<void> _updateMiniMaxVoiceModify(String key, Object? value) async {
    final current = _effectiveProviderSettings;
    final voiceModify = current.extra['voice_modify'] is Map
        ? Map<String, Object?>.from(
            stringKeyedMapFromValue(current.extra['voice_modify']),
          )
        : <String, Object?>{};
    if (value == null || (value is String && value.trim().isEmpty)) {
      voiceModify.remove(key);
    } else {
      voiceModify[key] = value;
    }
    await _updateExtra('voice_modify', voiceModify);
  }

  Future<void> _updateMiniMaxTimbreWeights(String raw) async {
    try {
      await _updateExtra('timbre_weights', _parseMiniMaxTimbreWeights(raw));
    } catch (error) {
      if (!mounted) return;
      _showSettingsTestErrorDialog(
        context: context,
        title: openHandLocalizedText(
          context,
          zh: '混合音色格式无效',
          en: 'Invalid Voice Mix',
        ),
        targetLabel: 'MiniMax timbre_weights',
        error: error,
      );
    }
  }

  Future<void> _pickAiModel() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final settingsController = context.read<SettingsController>();
    final latestModels = settingsController.aiModels;
    final current = _effectiveProviderSettings;
    final picked = await showModelSearchSelector(
      context: context,
      models: latestModels,
      selectedConfigId: current.modelConfigId,
      selectedModelId: current.modelId,
      recentSelections: widget.recentModelSelections,
      modelFilter: AiTtsPlaybackService.supportsAudioGenerationModel,
    );
    if (!mounted || picked == null) return;
    await settingsController.addRecentModelSelection(picked.$1, picked.$2);
    await _updateCurrent(
      (current) => _normalizeProviderSettingsForCurrentModel(
        current.copyWith(modelConfigId: picked.$1, modelId: picked.$2),
        latestModels,
      ),
    );
  }
}

class _AiTtsProviderDragFeedbackCard extends StatelessWidget {
  const _AiTtsProviderDragFeedbackCard({
    required this.priorityIndex,
    required this.label,
    required this.enabled,
    required this.width,
  });

  final int priorityIndex;
  final String label;
  final bool enabled;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: math.min(360, width),
        maxWidth: width,
        maxHeight: _aiTtsDragFeedbackMaxHeight,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: kOpenHandBorderRadius18,
          color: Color.alphaBlend(
            colorScheme.primary.withValues(alpha: enabled ? 0.055 : 0),
            colorScheme.surfaceContainerHigh,
          ),
          border: Border.all(
            color: colorScheme.primary.withValues(alpha: 0.30),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.18),
              blurRadius: 28,
              spreadRadius: 1,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: _aiTtsDragHandleSize,
                    height: _aiTtsDragHandleSize,
                    decoration: BoxDecoration(
                      borderRadius: kOpenHandBorderRadius12,
                      color: colorScheme.primaryContainer.withValues(
                        alpha: 0.68,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.drag_indicator_rounded,
                      size: 20,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                  kOpenHandHGap10,
                  _AiTtsPriorityBadge(index: priorityIndex),
                  kOpenHandHGap8,
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  _AiTtsStatusBadge(enabled: enabled),
                ],
              ),
              kOpenHandGap12,
              for (var row = 0; row < 3; row++) ...[
                FractionallySizedBox(
                  widthFactor: row == 2 ? 0.56 : 1,
                  child: Container(
                    height: 18,
                    decoration: BoxDecoration(
                      borderRadius: kOpenHandPillBorderRadius,
                      color: colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.86 - row * 0.12,
                      ),
                    ),
                  ),
                ),
                if (row != 2) kOpenHandGap8,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AiProviderInsertionGuide extends StatelessWidget {
  const _AiProviderInsertionGuide({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    final motionEnabled = _settingsMotionEnabled(context);
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary.withValues(alpha: 0.82);
    return ClipRect(
      child: AnimatedSize(
        duration: motionEnabled ? kOpenHandMotion220 : Duration.zero,
        reverseDuration: motionEnabled ? kOpenHandMotion180 : Duration.zero,
        curve: kOpenHandEntranceCurve,
        child: AnimatedOpacity(
          duration: motionEnabled ? kOpenHandMotion180 : Duration.zero,
          opacity: visible ? 1 : 0,
          child: SizedBox(
            height: visible ? 12 : 0,
            child: Center(
              child: FractionallySizedBox(
                widthFactor: 0.94,
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    borderRadius: kOpenHandPillBorderRadius,
                    color: color,
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.28),
                        blurRadius: 10,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AiProviderDragHandleFrame extends StatelessWidget {
  const _AiProviderDragHandleFrame({required this.opacity});

  final double opacity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: openHandLocalizedText(context, zh: '拖动调整优先级', en: 'Drag'),
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: AnimatedOpacity(
          duration: openHandMotionDuration(context, kOpenHandMotion180),
          opacity: opacity,
          child: Container(
            width: _aiTtsDragHandleSize,
            height: _aiTtsDragHandleSize,
            margin: const EdgeInsets.only(right: 10, top: 1),
            decoration: BoxDecoration(
              borderRadius: kOpenHandBorderRadius12,
              color: theme.colorScheme.surfaceContainerHigh,
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.74),
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
    );
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
        borderRadius: kOpenHandPillBorderRadius,
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
        borderRadius: kOpenHandPillBorderRadius,
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Text(
        enabled
            ? openHandLocalizedText(context, zh: '启用', en: 'On')
            : openHandLocalizedText(context, zh: '停用', en: 'Off'),
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// AI 服务卡片右上角圆形操作按钮的统一样式（展开、试听等共用）。
ButtonStyle _aiCardActionButtonStyle(ThemeData theme) {
  return IconButton.styleFrom(
    shape: const CircleBorder(),
    padding: EdgeInsets.zero,
    minimumSize: const Size.square(_aiTtsCardActionSize),
    fixedSize: const Size.square(_aiTtsCardActionSize),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    backgroundColor: theme.colorScheme.surfaceContainerHighest.withValues(
      alpha: _aiCardActionEnabledAlpha,
    ),
    foregroundColor: theme.colorScheme.onSurfaceVariant,
    disabledBackgroundColor: theme.colorScheme.surfaceContainerHighest
        .withValues(alpha: _aiCardActionDisabledAlpha),
    disabledForegroundColor: theme.colorScheme.onSurfaceVariant.withValues(
      alpha: _aiCardActionDisabledAlpha,
    ),
  );
}

class _AiProviderCardExpandButton extends StatelessWidget {
  const _AiProviderCardExpandButton({
    required this.expanded,
    required this.enabled,
    required this.onPressed,
  });

  final bool expanded;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final duration = openHandMotionDuration(context, kOpenHandMotion260);
    return Tooltip(
      message: !enabled
          ? openHandLocalizedText(context, zh: '启用后可展开', en: 'Enable to expand')
          : expanded
          ? openHandLocalizedText(
              context,
              zh: '折叠服务卡片',
              en: 'Collapse provider',
            )
          : openHandLocalizedText(context, zh: '展开服务卡片', en: 'Expand provider'),
      child: SizedBox.square(
        dimension: _aiTtsCardActionSize,
        child: IconButton.filledTonal(
          onPressed: enabled ? onPressed : null,
          style: _aiCardActionButtonStyle(theme),
          icon: AnimatedRotation(
            turns: enabled && expanded ? 0 : 0.5,
            duration: duration,
            curve: kOpenHandEntranceCurve,
            child: const Icon(Icons.expand_less_rounded, size: 22),
          ),
        ),
      ),
    );
  }
}

class _AiTtsTestButton extends StatelessWidget {
  const _AiTtsTestButton({
    required this.testing,
    required this.onPressed,
    this.tooltip,
  });

  final bool testing;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message:
          tooltip ??
          openHandLocalizedText(context, zh: '测试 TTS 服务', en: 'Test TTS'),
      child: SizedBox.square(
        dimension: _aiTtsCardActionSize,
        child: IconButton.filledTonal(
          onPressed: onPressed,
          style: _aiCardActionButtonStyle(theme),
          icon: testing
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.play_arrow_rounded, size: 22),
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
        borderRadius: kOpenHandBorderRadius14,
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
          kOpenHandGap10,
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

class _AiTtsToggleField extends StatelessWidget {
  const _AiTtsToggleField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: kOpenHandBorderRadius12,
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: Border.all(
          color: value
              ? theme.colorScheme.primary.withValues(alpha: 0.32)
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.58),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          _SettingsSwitch(value: value, onChanged: onChanged),
        ],
      ),
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
    return _SettingsStringDropdown(
      label: label,
      value: value,
      options: [
        for (final option in options)
          _SettingsStringDropdownOption(
            option.value,
            _localizedTtsCatalogOptionLabel(context, option),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

class _SettingsStringDropdownOption {
  const _SettingsStringDropdownOption(this.value, this.label);

  final String value;
  final String label;
}

class _SettingsStringDropdown extends StatelessWidget {
  const _SettingsStringDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<_SettingsStringDropdownOption> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final normalized = value.trim();
    final hasValue = options.any((option) => option.value == normalized);
    final effectiveOptions = options.isEmpty
        ? <_SettingsStringDropdownOption>[
            _SettingsStringDropdownOption(
              normalized,
              normalized.isEmpty
                  ? _settingsHelperDefaultLabel(context)
                  : _humanizedDropdownValue(context, normalized),
            ),
          ]
        : hasValue || normalized.isEmpty
        ? options
        : <_SettingsStringDropdownOption>[
            _SettingsStringDropdownOption(
              normalized,
              openHandLocalizedText(
                context,
                zh: '当前配置：${_humanizedDropdownValue(context, normalized)}',
                en: 'Current: ${_humanizedDropdownValue(context, normalized)}',
              ),
            ),
            ...options,
          ];
    final selected =
        effectiveOptions.any((option) => option.value == normalized)
        ? normalized
        : effectiveOptions.first.value;
    return AnimatedDropdownButtonFormField<String>(
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

class _AiTtsProviderTextField extends StatefulWidget {
  const _AiTtsProviderTextField({
    required this.label,
    required this.value,
    required this.onSubmitted,
    this.obscure = false,
    this.maxLines = 1,
  });

  final String label;
  final String value;
  final ValueChanged<String> onSubmitted;
  final bool obscure;
  final int maxLines;

  @override
  State<_AiTtsProviderTextField> createState() =>
      _AiTtsProviderTextFieldState();
}

class _AiTtsProviderTextFieldState extends State<_AiTtsProviderTextField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late final OpenHandDebouncer _commitDebouncer = OpenHandDebouncer(
    delay: _commitDebounceDelay,
  );
  static const Duration _commitDebounceDelay = Duration(milliseconds: 420);
  String? _lastCommittedValue;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focusNode = FocusNode()..addListener(_handleFocusChanged);
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
    _commitDebouncer.dispose();
    _focusNode.removeListener(_handleFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      decoration: InputDecoration(labelText: widget.label),
      obscureText: widget.obscure,
      maxLines: widget.obscure ? 1 : widget.maxLines,
      enableSuggestions: !widget.obscure,
      autocorrect: !widget.obscure,
      onChanged: _scheduleCommit,
      onSubmitted: _commit,
      onEditingComplete: () => _commit(_controller.text),
    );
  }

  void _handleFocusChanged() {
    if (!_focusNode.hasFocus) _commit(_controller.text);
  }

  void _scheduleCommit(String raw) {
    _commitDebouncer.schedule(() => _commit(raw));
  }

  void _commit(String raw) {
    _commitDebouncer.cancel();
    final value = raw.trim();
    if (value == _lastCommittedValue || value == widget.value) return;
    _lastCommittedValue = value;
    widget.onSubmitted(value);
  }
}

class _AiTtsProviderNumberField extends StatefulWidget {
  const _AiTtsProviderNumberField({
    required this.label,
    required this.value,
    required this.range,
    required this.onChanged,
  });

  final String label;
  final double value;
  final _TtsNumberRange range;
  final ValueChanged<double> onChanged;

  @override
  State<_AiTtsProviderNumberField> createState() =>
      _AiTtsProviderNumberFieldState();
}

class _AiTtsProviderNumberFieldState extends State<_AiTtsProviderNumberField> {
  double? _draftValue;

  double get _effectiveValue {
    return (_draftValue ?? widget.value)
        .clamp(widget.range.min, widget.range.max)
        .toDouble();
  }

  @override
  void didUpdateWidget(covariant _AiTtsProviderNumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value || oldWidget.range != widget.range) {
      _draftValue = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final clamped = _effectiveValue;
    final range = widget.range;
    return InputDecorator(
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: '${_formatValue(range.min)} - ${_formatValue(range.max)}',
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _AiTtsStepperButton(
                icon: Icons.remove_rounded,
                onPressed: clamped <= range.min
                    ? null
                    : () => _commit(clamped - range.step),
              ),
              Expanded(
                child: Slider(
                  min: range.min,
                  max: range.max,
                  divisions: range.divisions,
                  value: clamped,
                  label: _formatValue(clamped),
                  onChanged: _preview,
                  onChangeEnd: _commit,
                ),
              ),
              _AiTtsStepperButton(
                icon: Icons.add_rounded,
                onPressed: clamped >= range.max
                    ? null
                    : () => _commit(clamped + range.step),
              ),
              kOpenHandHGap10,
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 54),
                child: Text(
                  _formatValue(clamped),
                  textAlign: TextAlign.right,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontFeatures: const <ui.FontFeature>[
                      ui.FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _preview(double raw) {
    setState(() => _draftValue = widget.range.snap(raw));
  }

  void _commit(double raw) {
    final next = widget.range.snap(raw);
    setState(() => _draftValue = null);
    if ((next - widget.value).abs() < 0.0001) return;
    widget.onChanged(next);
  }

  static String _formatValue(double value) {
    return value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 2);
  }
}

class _AiTtsStepperButton extends StatelessWidget {
  const _AiTtsStepperButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 30,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          backgroundColor: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.58),
        ),
      ),
    );
  }
}

List<_SettingsStringDropdownOption> _translationLanguageDropdownOptions(
  BuildContext context,
  List<AiTranslationCatalogOption> options,
) {
  return [
    for (final option in options)
      _SettingsStringDropdownOption(
        option.value,
        _localizedLanguageCodeLabel(
          context,
          option.value,
          fallback: option.label,
        ),
      ),
  ];
}

String _localizedTtsCatalogOptionLabel(
  BuildContext context,
  AiTtsCatalogOption option,
) {
  final english = option.enLabel?.trim();
  if (english?.isNotEmpty == true) {
    return openHandLocalizedText(context, zh: option.label, en: english!);
  }
  final languageLabel = _localizedLanguageCodeLabel(
    context,
    option.value,
    fallback: '',
  );
  if (languageLabel.isNotEmpty) return languageLabel;
  return _localizedVoiceLabel(context, option.label);
}

String _humanizedDropdownValue(BuildContext context, String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    return _settingsHelperDefaultLabel(context);
  }
  final languageLabel = _localizedLanguageCodeLabel(
    context,
    normalized,
    fallback: '',
  );
  if (languageLabel.isNotEmpty) return languageLabel;
  final humanized = normalized
      .replaceFirst(
        RegExp(
          r'^(?:zh-CN|zh-TW|en-US|en-GB|ja-JP|ko-KR|fr-FR|de-DE|[a-z]{2})[-_]',
          caseSensitive: false,
        ),
        '',
      )
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .replaceAll(RegExp(r'\bbigtts\b', caseSensitive: false), '')
      .replaceAll(kInlineWhitespacePattern, ' ')
      .trim();
  return _localizedVoiceLabel(
    context,
    humanized.isEmpty ? normalized : humanized,
  );
}

String _localizedLanguageCodeLabel(
  BuildContext context,
  String value, {
  required String fallback,
}) {
  final normalized = value.trim();
  final label = switch (normalized) {
    'auto' => (zh: '自动检测', en: 'Auto detect'),
    'zh' || 'zh-CN' || 'zh-CHS' => (zh: '简体中文', en: 'Simplified Chinese'),
    'zh-TW' => (zh: '繁体中文', en: 'Traditional Chinese'),
    'en' => (zh: '英语', en: 'English'),
    'en-US' => (zh: '英语（美国）', en: 'English (US)'),
    'en-GB' => (zh: '英语（英国）', en: 'English (UK)'),
    'ja' || 'ja-JP' => (zh: '日语', en: 'Japanese'),
    'ko' || 'ko-KR' => (zh: '韩语', en: 'Korean'),
    'fr' || 'fr-FR' => (zh: '法语', en: 'French'),
    'de' || 'de-DE' => (zh: '德语', en: 'German'),
    'es' => (zh: '西班牙语', en: 'Spanish'),
    'ru' => (zh: '俄语', en: 'Russian'),
    'it' => (zh: '意大利语', en: 'Italian'),
    'pt' => (zh: '葡萄牙语', en: 'Portuguese'),
    'vi' => (zh: '越南语', en: 'Vietnamese'),
    'th' => (zh: '泰语', en: 'Thai'),
    'id' => (zh: '印度尼西亚语', en: 'Indonesian'),
    'ar' => (zh: '阿拉伯语', en: 'Arabic'),
    'tr' => (zh: '土耳其语', en: 'Turkish'),
    'hi' => (zh: '印地语', en: 'Hindi'),
    'he' => (zh: '希伯来语', en: 'Hebrew'),
    'nl' => (zh: '荷兰语', en: 'Dutch'),
    'pl' => (zh: '波兰语', en: 'Polish'),
    'sv' => (zh: '瑞典语', en: 'Swedish'),
    'da' => (zh: '丹麦语', en: 'Danish'),
    _ => null,
  };
  if (label != null) {
    return openHandLocalizedText(context, zh: label.zh, en: label.en);
  }
  return _stripTrailingLanguageCode(fallback);
}

String _localizedVoiceLabel(BuildContext context, String rawLabel) {
  final trimmed = rawLabel.trim();
  if (trimmed.isEmpty) return trimmed;
  final exact = switch (trimmed) {
    '自动匹配系统默认音色' => (zh: '自动匹配系统默认音色', en: 'Auto system voice'),
    '有道默认发音人' => (zh: '有道默认发音人', en: 'Youdao default voice'),
    _ => null,
  };
  if (exact != null) {
    return openHandLocalizedText(context, zh: exact.zh, en: exact.en);
  }
  const suffixes = <String, ({String zh, String en})>{
    'English Female': (zh: '英语女声', en: 'English female voice'),
    'English Male': (zh: '英语男声', en: 'English male voice'),
    'English': (zh: '英语', en: 'English'),
    '中文女声': (zh: '中文女声', en: 'Chinese female voice'),
    '中文男声': (zh: '中文男声', en: 'Chinese male voice'),
    '繁中女声': (zh: '繁体中文女声', en: 'Traditional Chinese female voice'),
    '日本語': (zh: '日语', en: 'Japanese'),
    '女声': (zh: '女声', en: 'Female voice'),
    '男声': (zh: '男声', en: 'Male voice'),
    '童声': (zh: '童声', en: 'Child voice'),
  };
  for (final entry in suffixes.entries) {
    final suffix = entry.key;
    final marker = ' - $suffix';
    if (trimmed.endsWith(marker)) {
      final prefix = trimmed
          .substring(0, trimmed.length - marker.length)
          .trim();
      final localizedSuffix = openHandLocalizedText(
        context,
        zh: entry.value.zh,
        en: entry.value.en,
      );
      return prefix.isEmpty ? localizedSuffix : '$prefix - $localizedSuffix';
    }
  }
  return _stripTrailingLanguageCode(trimmed);
}

String _stripTrailingLanguageCode(String label) {
  return label
      .replaceFirst(
        RegExp(r'\s+(?:[a-z]{2,3}(?:-[A-Z]{2,4})?|zh-[A-Z]{2,4})$'),
        '',
      )
      .trim();
}

String _translationProviderLabel(
  BuildContext context,
  AiTranslationProvider provider,
) {
  switch (provider) {
    case AiTranslationProvider.ai:
      return openHandLocalizedText(context, zh: 'AI 翻译', en: 'AI Translation');
    case AiTranslationProvider.youdao:
      return openHandLocalizedText(context, zh: '有道翻译', en: 'Youdao Translate');
    case AiTranslationProvider.google:
      return openHandLocalizedText(context, zh: '谷歌翻译', en: 'Google Translate');
    case AiTranslationProvider.bing:
      return 'Bing Translate';
    case AiTranslationProvider.apple:
      return openHandLocalizedText(context, zh: '苹果翻译', en: 'Apple Translate');
    case AiTranslationProvider.baidu:
      return openHandLocalizedText(context, zh: '百度翻译', en: 'Baidu Translate');
    case AiTranslationProvider.doubao:
      return openHandLocalizedText(context, zh: '豆包翻译', en: 'Doubao Translate');
  }
}

String _translationProviderHint(
  BuildContext context,
  AiTranslationProvider provider,
) {
  switch (provider) {
    case AiTranslationProvider.ai:
      return openHandLocalizedText(
        context,
        zh: '复用全局模型供应商执行翻译，适合保留 Markdown 与代码结构。',
        en: 'Uses configured model providers and preserves Markdown/code structure.',
      );
    case AiTranslationProvider.youdao:
      return openHandLocalizedText(
        context,
        zh: '调用有道智云文本翻译接口，需 API Key 与 API Secret。',
        en: 'Calls Youdao text translation with API key and secret.',
      );
    case AiTranslationProvider.google:
      return openHandLocalizedText(
        context,
        zh: '调用 Google Translate API，需 API Key。',
        en: 'Calls Google Translate API with an API key.',
      );
    case AiTranslationProvider.bing:
      return openHandLocalizedText(
        context,
        zh: '调用 Microsoft Translator，需订阅密钥，可选区域 Region。',
        en: 'Calls Microsoft Translator with subscription key and optional region.',
      );
    case AiTranslationProvider.apple:
      return openHandLocalizedText(
        context,
        zh: 'Apple 官方本地翻译 SDK 不直接暴露给 Flutter；这里接入本机/私有桥接服务。',
        en: 'Apple local translation is bridged through a local/private service.',
      );
    case AiTranslationProvider.baidu:
      return openHandLocalizedText(
        context,
        zh: '调用百度通用翻译接口，需 App ID 与 Secret Key。',
        en: 'Calls Baidu general translation with App ID and secret key.',
      );
    case AiTranslationProvider.doubao:
      return openHandLocalizedText(
        context,
        zh: '调用火山引擎机器翻译大模型，支持 API Key 或旧版 App Key 鉴权。',
        en: 'Calls Volcengine machine translation with API key or legacy app access key.',
      );
  }
}

String _translationPrimaryCredentialLabel(AiTranslationProvider provider) {
  switch (provider) {
    case AiTranslationProvider.bing:
      return 'Subscription Key';
    case AiTranslationProvider.youdao:
    case AiTranslationProvider.google:
    case AiTranslationProvider.apple:
    case AiTranslationProvider.doubao:
    case AiTranslationProvider.baidu:
    case AiTranslationProvider.ai:
      return 'API Key';
  }
}

String _translationSecondaryCredentialLabel(AiTranslationProvider provider) {
  if (provider == AiTranslationProvider.doubao) return 'Access Key（旧版）';
  return provider == AiTranslationProvider.baidu ? 'Secret Key' : 'API Secret';
}

String? _translationProviderReadinessError(
  BuildContext context,
  AiTranslationProviderSettings settings, {
  required List<AiModelConfig> availableModels,
}) {
  final missing = <String>[];
  void requireField(String value, String label) {
    if (value.trim().isEmpty) missing.add(label);
  }

  switch (settings.provider) {
    case AiTranslationProvider.ai:
      if (settings.modelConfigId.trim().isEmpty ||
          settings.modelId.trim().isEmpty) {
        if (availableModels.isEmpty) {
          missing.add(openHandLocalizedText(context, zh: '可用模型', en: 'models'));
        }
      }
    case AiTranslationProvider.youdao:
      requireField(settings.apiKey, 'API Key');
      requireField(settings.apiSecret, 'API Secret');
    case AiTranslationProvider.google:
      requireField(settings.apiKey, 'API Key');
    case AiTranslationProvider.bing:
      requireField(settings.apiKey, 'Subscription Key');
    case AiTranslationProvider.apple:
      requireField(
        settings.endpoint,
        openHandLocalizedText(context, zh: '桥接服务地址', en: 'bridge endpoint'),
      );
    case AiTranslationProvider.baidu:
      requireField(settings.appId, 'App ID');
      requireField(settings.apiSecret, 'Secret Key');
    case AiTranslationProvider.doubao:
      if (settings.apiKey.trim().isEmpty &&
          (settings.appId.trim().isEmpty ||
              settings.apiSecret.trim().isEmpty)) {
        missing.add('API Key / App ID + Access Key');
      }
  }
  if (missing.isEmpty) return null;
  return openHandLocalizedText(
    context,
    zh: '请先补全 ${_translationProviderLabel(context, settings.provider)} 配置：${missing.join('、')}',
    en: 'Complete ${_translationProviderLabel(context, settings.provider)} first: ${missing.join(', ')}',
  );
}

String _ttsProviderLabel(BuildContext context, AiTtsProvider provider) {
  switch (provider) {
    case AiTtsProvider.ai:
      return openHandLocalizedText(context, zh: 'AI 语音', en: 'AI Speech');
    case AiTtsProvider.system:
      return openHandLocalizedText(context, zh: '系统 TTS', en: 'System TTS');
    case AiTtsProvider.xfyun:
      return openHandLocalizedText(context, zh: '讯飞 TTS', en: 'Xfyun TTS');
    case AiTtsProvider.youdao:
      return openHandLocalizedText(context, zh: '有道 TTS', en: 'Youdao TTS');
    case AiTtsProvider.bing:
      return 'Bing TTS';
    case AiTtsProvider.google:
      return 'Google TTS';
    case AiTtsProvider.baidu:
      return openHandLocalizedText(context, zh: '百度 TTS', en: 'Baidu TTS');
    case AiTtsProvider.doubao:
      return openHandLocalizedText(context, zh: '豆包 TTS', en: 'Doubao TTS');
    case AiTtsProvider.mimo:
      return 'Mimo TTS';
    case AiTtsProvider.apple:
      return openHandLocalizedText(context, zh: '苹果 TTS', en: 'Apple TTS');
  }
}

String _ttsProviderHint(BuildContext context, AiTtsProvider provider) {
  switch (provider) {
    case AiTtsProvider.ai:
      return openHandLocalizedText(
        context,
        zh: '复用全局模型供应商生成语音，仅支持多模态音频生成模型。',
        en: 'Uses configured multimodal audio-generation model providers.',
      );
    case AiTtsProvider.system:
      return openHandLocalizedText(
        context,
        zh: '默认使用本机系统语音能力，无需密钥。',
        en: 'Uses local system speech without credentials.',
      );
    case AiTtsProvider.apple:
      return openHandLocalizedText(
        context,
        zh: '在 Apple 平台优先匹配系统语音；其他平台会按能力回退。',
        en: 'Prefers Apple system voices and falls back by capability.',
      );
    case AiTtsProvider.xfyun:
      return openHandLocalizedText(
        context,
        zh: '讯飞在线 TTS，使用 WebSocket 与 HMAC 鉴权。',
        en: 'Xfyun online TTS with WebSocket and HMAC auth.',
      );
    case AiTtsProvider.youdao:
      return openHandLocalizedText(
        context,
        zh: '保留有道 TTS 参数；服务接入不可用时自动回退。',
        en: 'Keeps Youdao TTS parameters and falls back when unavailable.',
      );
    case AiTtsProvider.bing:
      return openHandLocalizedText(
        context,
        zh: '保留 Bing 语音参数；浏览器端可由系统语音兜底。',
        en: 'Keeps Bing voice parameters; browser runtime can fallback.',
      );
    case AiTtsProvider.google:
      return openHandLocalizedText(
        context,
        zh: '保留 Google TTS 参数；服务不可用时自动回退。',
        en: 'Keeps Google TTS parameters and falls back when unavailable.',
      );
    case AiTtsProvider.baidu:
      return openHandLocalizedText(
        context,
        zh: '填写 Access Token 后可调用百度语音合成接口。',
        en: 'Uses Baidu speech synthesis with an access token.',
      );
    case AiTtsProvider.doubao:
      return openHandLocalizedText(
        context,
        zh: '豆包 V3 在线语音合成，需 API Key、Resource ID 与音色。',
        en: 'Doubao V3 online TTS with API key, resource ID, and speaker.',
      );
    case AiTtsProvider.mimo:
      return openHandLocalizedText(
        context,
        zh: '小米 Mimo V2.5 语音合成，支持预置音色、风格提示和音频格式配置。',
        en: 'Xiaomi Mimo V2.5 TTS with preset voices, style prompts, and audio formats.',
      );
  }
}

String? _selectedProviderModelLabel({
  required String configId,
  required String modelId,
  required List<AiModelConfig> models,
}) {
  final normalizedConfigId = configId.trim();
  final normalizedModelId = modelId.trim();
  if (normalizedConfigId.isEmpty || normalizedModelId.isEmpty) return null;
  for (final model in models) {
    if (model.id == normalizedConfigId) {
      final providerLabel = model.providerLabel.trim().isEmpty
          ? model.name
          : model.providerLabel;
      return '$providerLabel · $normalizedModelId';
    }
  }
  return normalizedModelId;
}

AiModelConfig? _selectedAiTtsModel({
  required AiTtsProviderSettings settings,
  required List<AiModelConfig> models,
}) {
  final configId = settings.modelConfigId.trim();
  final modelId = settings.modelId.trim();
  if (configId.isEmpty || modelId.isEmpty) return null;
  for (final model in models) {
    if (model.id == configId && model.allModelIds.contains(modelId)) {
      return model.copyWith(modelId: modelId);
    }
  }
  return null;
}

bool _settingsJsonEquals(Object? left, Object? right) {
  return jsonEncode(left) == jsonEncode(right);
}

List<T>? _settingsReorderedProviderPriorityAt<T>(
  List<T> priority,
  T source,
  int insertIndex,
) {
  final oldIndex = priority.indexOf(source);
  if (oldIndex < 0) return null;

  final next = List<T>.from(priority);
  final item = next.removeAt(oldIndex);
  final adjustedIndex = oldIndex < insertIndex ? insertIndex - 1 : insertIndex;
  next.insert(adjustedIndex.clamp(0, next.length), item);
  return listEquals(next, priority) ? null : next;
}

int _settingsProviderPriorityInsertIndex<T>(
  List<T> priority,
  T source,
  Offset globalOffset,
  Map<T, GlobalKey> itemKeys,
) {
  final sourceIndex = priority.indexOf(source);
  if (sourceIndex < 0) return priority.length;

  for (var index = 0; index < priority.length; index++) {
    final key = itemKeys[priority[index]];
    final box = key?.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || box.size.isEmpty) continue;

    final topLeft = box.localToGlobal(Offset.zero);
    final top = topLeft.dy;
    final bottom = top + box.size.height;
    if (globalOffset.dy < top) return index;
    if (globalOffset.dy > bottom) continue;

    if (index == sourceIndex) {
      final center = top + box.size.height / 2;
      return globalOffset.dy < center ? index : index + 1;
    }
    return sourceIndex > index ? index : index + 1;
  }

  return priority.length;
}

List<AiModelConfig> _ttsAudioGenerationModels(List<AiModelConfig> models) {
  return models
      .where(
        (config) => config.allModelIds.any(
          (modelId) => AiTtsPlaybackService.supportsAudioGenerationModel(
            config,
            modelId,
          ),
        ),
      )
      .toList(growable: false);
}

AiModelConfig? _ttsFallbackAudioModel(SettingsController settingsController) {
  final selected = settingsController.selectedAiModel;
  if (selected == null ||
      !AiTtsPlaybackService.supportsAudioGenerationModel(
        selected,
        selected.modelId,
      )) {
    return null;
  }
  return selected;
}

enum _TtsNumberKind { speed, volume, pitch }

class _TtsNumberRange {
  const _TtsNumberRange(this.min, this.max, {this.step = 1});

  final double min;
  final double max;
  final double step;

  int? get divisions {
    if (step <= 0) return null;
    final count = ((max - min) / step).round();
    return count > 0 && count <= 1000 ? count : null;
  }

  double snap(double raw) {
    final clamped = raw.clamp(min, max).toDouble();
    if (step <= 0) return clamped;
    final snapped = min + ((clamped - min) / step).round() * step;
    return snapped.clamp(min, max).toDouble();
  }
}

_TtsNumberRange _ttsNumberRange(AiTtsProvider provider, _TtsNumberKind kind) {
  switch (provider) {
    case AiTtsProvider.xfyun:
      return const _TtsNumberRange(0, 100);
    case AiTtsProvider.baidu:
      return const _TtsNumberRange(0, 15);
    case AiTtsProvider.doubao:
      return kind == _TtsNumberKind.pitch
          ? const _TtsNumberRange(-12, 12)
          : const _TtsNumberRange(-50, 100);
    case AiTtsProvider.mimo:
      return switch (kind) {
        _TtsNumberKind.speed => const _TtsNumberRange(0.5, 2, step: 0.05),
        _TtsNumberKind.volume => const _TtsNumberRange(0, 1, step: 0.05),
        _TtsNumberKind.pitch => const _TtsNumberRange(0.5, 2, step: 0.05),
      };
    case AiTtsProvider.google:
      return switch (kind) {
        _TtsNumberKind.speed => const _TtsNumberRange(0.25, 4, step: 0.05),
        _TtsNumberKind.volume => const _TtsNumberRange(-96, 16),
        _TtsNumberKind.pitch => const _TtsNumberRange(-20, 20),
      };
    case AiTtsProvider.bing:
      return switch (kind) {
        _TtsNumberKind.speed => const _TtsNumberRange(0.5, 2, step: 0.05),
        _TtsNumberKind.volume => const _TtsNumberRange(0, 100),
        _TtsNumberKind.pitch => const _TtsNumberRange(-20, 20),
      };
    case AiTtsProvider.ai:
      return switch (kind) {
        _TtsNumberKind.speed => const _TtsNumberRange(0.25, 4, step: 0.05),
        _TtsNumberKind.volume => const _TtsNumberRange(0, 1, step: 0.05),
        _TtsNumberKind.pitch => const _TtsNumberRange(-20, 20),
      };
    case AiTtsProvider.system:
    case AiTtsProvider.apple:
    case AiTtsProvider.youdao:
      return switch (kind) {
        _TtsNumberKind.speed => const _TtsNumberRange(0.5, 2, step: 0.05),
        _TtsNumberKind.volume => const _TtsNumberRange(0, 1, step: 0.05),
        _TtsNumberKind.pitch => const _TtsNumberRange(0.5, 2, step: 0.05),
      };
  }
}

_TtsNumberRange _aiTtsNumberRangeForModel({
  required AiProtocolType protocol,
  required String modelId,
  required _TtsNumberKind kind,
}) {
  if (AiTtsProviderCatalogs.usesMiniMaxSpeech(
    protocol: protocol,
    modelId: modelId,
  )) {
    return switch (kind) {
      _TtsNumberKind.speed => const _TtsNumberRange(0.5, 2, step: 0.05),
      _TtsNumberKind.volume => const _TtsNumberRange(0.1, 10, step: 0.1),
      _TtsNumberKind.pitch => const _TtsNumberRange(-12, 12),
    };
  }
  if (!AiTtsProviderCatalogs.usesStepFunSpeech(
    protocol: protocol,
    modelId: modelId,
  )) {
    return _ttsNumberRange(AiTtsProvider.ai, kind);
  }
  return switch (kind) {
    _TtsNumberKind.speed => const _TtsNumberRange(0.5, 2, step: 0.05),
    _TtsNumberKind.volume => const _TtsNumberRange(0.1, 2, step: 0.05),
    _TtsNumberKind.pitch => _ttsNumberRange(AiTtsProvider.ai, kind),
  };
}

List<AiTtsCatalogOption> _miniMaxVoiceOptionsFromPayload(
  Map<String, Object?> payload,
) {
  final options = <AiTtsCatalogOption>[];
  for (final section in const <String>[
    'system_voice',
    'voice_cloning',
    'voice_generation',
  ]) {
    final entries = payload[section];
    if (entries is! List) continue;
    for (final raw in entries) {
      if (raw is! Map) continue;
      final voice = stringKeyedMapFromValue(raw);
      final id = optionalStringFromValue(voice['voice_id']);
      if (id == null) continue;
      final name = optionalStringFromValue(voice['voice_name']);
      final descriptions = stringListFromListValue(voice['description']);
      final label = <String>[
        name ?? id,
        if (descriptions.isNotEmpty) descriptions.first,
      ].join(' · ');
      options.add(AiTtsCatalogOption(id, label, label));
    }
  }
  return _settingsUniqueTtsOptions(options);
}

List<String> _miniMaxDelimitedValues(String raw, {required String separator}) {
  return raw
      .split(separator)
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toSet()
      .take(100)
      .toList(growable: false);
}

String _miniMaxTimbreWeightsText(Object? raw) {
  if (raw is! List) return '';
  return raw
      .whereType<Map>()
      .map(stringKeyedMapFromValue)
      .map((item) {
        final voiceId = optionalStringFromValue(item['voice_id']);
        final weight = optionalIntFromValue(item['weight']);
        return voiceId == null || weight == null ? null : '$voiceId:$weight';
      })
      .whereType<String>()
      .join(', ');
}

List<Map<String, Object?>> _parseMiniMaxTimbreWeights(String raw) {
  final normalized = raw.trim();
  if (normalized.isEmpty) return const <Map<String, Object?>>[];
  final entries = normalized
      .replaceAll('，', ',')
      .split(RegExp(r'[,\n]+'))
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
  if (entries.length > 4) {
    throw const FormatException('最多只能混合 4 个音色。');
  }
  final result = <Map<String, Object?>>[];
  final seen = <String>{};
  for (final entry in entries) {
    final separator = entry.lastIndexOf(':');
    if (separator <= 0 || separator >= entry.length - 1) {
      throw FormatException('请使用 voice_id:权重 格式：$entry');
    }
    final voiceId = entry.substring(0, separator).trim();
    final weight = int.tryParse(entry.substring(separator + 1).trim());
    if (voiceId.isEmpty || weight == null || weight < 1 || weight > 100) {
      throw FormatException('音色权重必须为 1–100：$entry');
    }
    if (!seen.add(voiceId)) {
      throw FormatException('音色不可重复：$voiceId');
    }
    result.add(<String, Object?>{'voice_id': voiceId, 'weight': weight});
  }
  return result;
}

List<AiTtsCatalogOption> _settingsUniqueTtsOptions(
  Iterable<AiTtsCatalogOption> options,
) {
  final seen = <String>{};
  return options
      .where((option) => seen.add(option.value))
      .toList(growable: false);
}

String _primaryCredentialLabel(AiTtsProvider provider) {
  switch (provider) {
    case AiTtsProvider.baidu:
      return 'API Key';
    case AiTtsProvider.bing:
      return 'Subscription Key';
    case AiTtsProvider.google:
      return 'API Key';
    default:
      return 'API Key';
  }
}

String _secondaryCredentialLabel(AiTtsProvider provider) {
  return provider == AiTtsProvider.baidu ? 'Secret Key' : 'API Secret / Token';
}

bool _needsSecondaryCredential(AiTtsProvider provider) {
  return provider == AiTtsProvider.xfyun ||
      provider == AiTtsProvider.youdao ||
      provider == AiTtsProvider.baidu;
}

bool _needsAppIdCredential(AiTtsProvider provider) {
  return provider == AiTtsProvider.xfyun;
}

bool _mimoUsesPresetVoice(AiTtsProviderSettings settings) {
  final model = '${settings.extra['model'] ?? 'mimo-v2.5-tts'}'.trim();
  return model.isEmpty || model == 'mimo-v2.5-tts';
}

bool _mimoUsesVoiceClone(AiTtsProviderSettings settings) {
  return '${settings.extra['model'] ?? ''}'.trim() ==
      'mimo-v2.5-tts-voiceclone';
}

String? _ttsProviderReadinessError(
  BuildContext context,
  AiTtsProviderSettings settings,
  List<AiModelConfig> availableModels, {
  AiModelConfig? fallbackModel,
}) {
  final missing = <String>[];
  void requireField(String value, String label) {
    if (value.trim().isEmpty) missing.add(label);
  }

  switch (settings.provider) {
    case AiTtsProvider.ai:
      final hasFallbackModel =
          fallbackModel != null &&
          AiTtsPlaybackService.supportsAudioGenerationModel(
            fallbackModel,
            fallbackModel.modelId,
          );
      if (settings.modelConfigId.trim().isEmpty ||
          settings.modelId.trim().isEmpty) {
        if (!hasFallbackModel &&
            _ttsAudioGenerationModels(availableModels).isEmpty) {
          missing.add(
            openHandLocalizedText(context, zh: '可用语音模型', en: 'models'),
          );
        } else if (!hasFallbackModel) {
          missing.add(openHandLocalizedText(context, zh: '语音模型', en: 'model'));
        }
      } else if (!availableModels.any(
        (config) =>
            config.id == settings.modelConfigId &&
            config.allModelIds.contains(settings.modelId) &&
            AiTtsPlaybackService.supportsAudioGenerationModel(
              config,
              settings.modelId,
            ),
      )) {
        missing.add(
          openHandLocalizedText(context, zh: '有效语音模型', en: 'valid model'),
        );
      }
    case AiTtsProvider.system:
    case AiTtsProvider.apple:
      break;
    case AiTtsProvider.xfyun:
      requireField(settings.appId, 'App ID');
      requireField(settings.apiKey, 'API Key');
      requireField(settings.apiSecret, 'API Secret');
    case AiTtsProvider.youdao:
      requireField(settings.apiKey, 'API Key');
      requireField(settings.apiSecret, 'API Secret');
    case AiTtsProvider.bing:
      requireField(settings.apiKey, 'Subscription Key');
      if (settings.region.trim().isEmpty && settings.endpoint.trim().isEmpty) {
        missing.add(_settingsHelperRegionLabel(context));
      }
    case AiTtsProvider.google:
      requireField(settings.apiKey, 'API Key');
    case AiTtsProvider.baidu:
      if (settings.accessToken.trim().isEmpty) {
        requireField(settings.apiKey, 'API Key');
        requireField(settings.apiSecret, 'Secret Key');
      }
    case AiTtsProvider.doubao:
      requireField(settings.apiKey, 'API Key');
    case AiTtsProvider.mimo:
      requireField(settings.apiKey, 'API Key');
      if (_mimoUsesPresetVoice(settings) && settings.voice.trim().isEmpty) {
        missing.add(openHandLocalizedText(context, zh: '音色', en: 'Voice'));
      }
      if (_mimoUsesVoiceClone(settings) &&
          '${settings.extra['voice_sample_path'] ?? ''}'.trim().isEmpty) {
        missing.add(_settingsHelperCloneSamplePathLabel(context));
      }
  }
  if (missing.isEmpty) return null;
  return openHandLocalizedText(
    context,
    zh: '请先补全 ${_ttsProviderLabel(context, settings.provider)} 配置：${missing.join('、')}',
    en: 'Complete ${_ttsProviderLabel(context, settings.provider)} first: ${missing.join(', ')}',
  );
}

double _ttsDragFeedbackWidth(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width - 96;
  return width.clamp(360.0, 960.0).toDouble();
}

String _audioEncodingExtraKey(AiTtsProvider provider) {
  return provider == AiTtsProvider.bing ? 'outputFormat' : 'audioEncoding';
}

String _defaultAudioEncoding(AiTtsProvider provider) {
  return provider == AiTtsProvider.bing
      ? 'audio-24khz-48kbitrate-mono-mp3'
      : 'MP3';
}

void _showSettingsTestErrorDialog({
  required BuildContext context,
  required String title,
  required String targetLabel,
  required Object error,
}) {
  OpenHandSnackBar.hideGlobal();
  showFriendlyErrorDetailsDialog(
    context,
    title: title,
    fullText: _settingsTestErrorDetails(
      context: context,
      title: title,
      targetLabel: targetLabel,
      error: error,
    ),
  );
}

String _settingsTestErrorDetails({
  required BuildContext context,
  required String title,
  required String targetLabel,
  required Object error,
}) {
  final message = _settingsFullErrorText(context, error);
  final buffer = StringBuffer()
    ..writeln(title)
    ..writeln(
      openHandLocalizedText(
        context,
        zh: '测试对象：$targetLabel',
        en: 'Test target: $targetLabel',
      ),
    )
    ..writeln()
    ..writeln(message);

  final rawResponse = error is AiMediaGenerationException
      ? error.rawResponseBody?.trim()
      : null;
  if (rawResponse != null &&
      rawResponse.isNotEmpty &&
      !message.contains(rawResponse)) {
    buffer
      ..writeln()
      ..writeln(
        openHandLocalizedText(context, zh: '原始响应：', en: 'Raw response:'),
      )
      ..writeln(rawResponse);
  }

  final targetedSuggestion = _settingsTargetedErrorSuggestion(context, error);
  if (targetedSuggestion != null) {
    buffer
      ..writeln()
      ..writeln(
        openHandLocalizedText(context, zh: '排查建议：', en: 'Troubleshooting:'),
      )
      ..writeln(targetedSuggestion);
  }
  return buffer.toString().trim();
}

String _settingsFullErrorText(BuildContext context, Object error) {
  if (error is TimeoutException) {
    final message = error.message?.trim();
    if (message != null && message.isNotEmpty) return message;
    return openHandLocalizedText(
      context,
      zh: '操作超时，请重试或适当增大超时时间。',
      en: 'The operation timed out. Try again or increase the timeout.',
    );
  }
  final raw = error.toString().trim();
  if (raw.isEmpty) {
    return openHandLocalizedText(context, zh: '未知错误', en: 'Unknown error');
  }
  return raw
      .replaceFirst(RegExp(r'^[A-Za-z0-9_.$]+Exception:\s*'), '')
      .replaceFirst(RegExp(r'^Bad state:\s*'), '')
      .trim();
}

String? _settingsTargetedErrorSuggestion(BuildContext context, Object error) {
  final message = _settingsFullErrorText(context, error).toLowerCase();
  if (message.contains('voice_id') &&
      (message.contains('does not exist') ||
          message.contains('do not have access'))) {
    return openHandLocalizedText(
      context,
      zh:
          '· 当前音色不属于该模型可用的系统音色，或账号没有该自定义音色权限。\n'
          '· 请先切换为下拉列表中的官方系统音色，例如 磁性男声（cixingnansheng）或活力女声（lively-girl）。\n'
          '· 如果必须使用自定义音色，请确认该 voice_id 已在 StepFun 控制台创建并对当前 API Key 可见。',
      en:
          '· The selected voice is not available for this model, or the account cannot access that custom voice.\n'
          '· Select an official system voice from the dropdown, such as Magnetic Male Voice (cixingnansheng) or Lively Female Voice (lively-girl).\n'
          '· If you need a custom voice, confirm that the voice_id exists in StepFun and is visible to the current API key.',
    );
  }
  return null;
}

String _compactSettingsPreview(String value) {
  const maxLength = 90;
  return clipText(collapseInlineWhitespace(value), maxLength);
}

bool _providerNeedsEndpoint(AiTtsProvider provider) {
  return provider == AiTtsProvider.xfyun ||
      provider == AiTtsProvider.baidu ||
      provider == AiTtsProvider.doubao ||
      provider == AiTtsProvider.mimo;
}

bool _providerNeedsCredentials(AiTtsProvider provider) {
  return provider != AiTtsProvider.system &&
      provider != AiTtsProvider.ai &&
      provider != AiTtsProvider.apple;
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
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.value}');
    // 失焦即提交：只挂 onSubmitted / onEditingComplete 的话，用鼠标点到别的
    // 输入框不会触发任何回调，用户改过的值会被静默丢弃，界面回退成旧值。
    _focusNode = FocusNode()
      ..addListener(() {
        if (!_focusNode.hasFocus) _commit(_controller.text);
      });
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
    _focusNode.dispose();
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
      focusNode: _focusNode,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.right,
      style: const TextStyle(
        fontSize: 12,
        fontFamily: kOpenHandMonospaceFontFamily,
      ),
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

class _SettingsIntSlider extends StatefulWidget {
  const _SettingsIntSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
    this.suffix = '',
  });

  final int value;
  final int min;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;
  final String suffix;

  @override
  State<_SettingsIntSlider> createState() => _SettingsIntSliderState();
}

class _SettingsIntSliderState extends State<_SettingsIntSlider> {
  int? _draftValue;

  int get _effectiveValue => _snap(_draftValue ?? widget.value);

  @override
  void didUpdateWidget(covariant _SettingsIntSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value ||
        oldWidget.min != widget.min ||
        oldWidget.max != widget.max ||
        oldWidget.step != widget.step) {
      _draftValue = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final clamped = _effectiveValue;
    final divisions = _divisions;
    final formatted = widget.suffix.isEmpty
        ? '$clamped'
        : '$clamped${widget.suffix}';
    return InputDecorator(
      decoration: InputDecoration(
        helperText: '${widget.min} - ${widget.max}',
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),
      child: Row(
        children: [
          _AiTtsStepperButton(
            icon: Icons.remove_rounded,
            onPressed: clamped <= widget.min
                ? null
                : () => _commit(clamped - widget.step),
          ),
          Expanded(
            child: Slider(
              min: widget.min.toDouble(),
              max: widget.max.toDouble(),
              divisions: divisions,
              value: clamped.toDouble(),
              label: formatted,
              onChanged: _preview,
              onChangeEnd: (raw) => _commit(raw.round()),
            ),
          ),
          _AiTtsStepperButton(
            icon: Icons.add_rounded,
            onPressed: clamped >= widget.max
                ? null
                : () => _commit(clamped + widget.step),
          ),
          kOpenHandHGap10,
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 58),
            child: Text(
              formatted,
              textAlign: TextAlign.right,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
                fontFeatures: const <ui.FontFeature>[
                  ui.FontFeature.tabularFigures(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  int? get _divisions {
    if (widget.step <= 0) return null;
    final count = ((widget.max - widget.min) / widget.step).round();
    return count > 0 && count <= 1000 ? count : null;
  }

  int _snap(int raw) {
    final clamped = raw.clamp(widget.min, widget.max).toInt();
    if (widget.step <= 0) return clamped;
    final snapped =
        widget.min +
        ((clamped - widget.min) / widget.step).round() * widget.step;
    return snapped.clamp(widget.min, widget.max).toInt();
  }

  void _preview(double raw) {
    setState(() => _draftValue = _snap(raw.round()));
  }

  void _commit(int raw) {
    final next = _snap(raw);
    setState(() => _draftValue = null);
    if (next == widget.value) return;
    widget.onChanged(next);
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
        borderRadius: kOpenHandBorderRadius4,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: foregroundColor),
          kOpenHandHGap3,
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
                kOpenHandGap8,
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
        borderRadius: BorderRadius.circular(kOpenHandRadius24),
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
                borderRadius: kOpenHandBorderRadius18,
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: colorScheme.onPrimaryContainer),
            ),
            kOpenHandHGap16,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleLarge),
                  kOpenHandGap6,
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
    final duration = openHandMotionDuration(context, kOpenHandMotion280);
    final reverseDuration = openHandMotionDuration(
      context,
      const Duration(milliseconds: 190),
    );

    return AnimatedSize(
      duration: duration,
      reverseDuration: reverseDuration,
      curve: kOpenHandSwitchInCurve,
      alignment: Alignment.topLeft,
      child: ClipRect(
        child: AnimatedSwitcher(
          duration: duration,
          reverseDuration: reverseDuration,
          switchInCurve: kOpenHandEntranceCurve,
          switchOutCurve: kOpenHandSwitchOutCurve,
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
                    ? kOpenHandSwitchOutCurve.transform(raw)
                    : kOpenHandEntranceCurve.transform(raw);
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
      duration: openHandMotionDuration(context, kOpenHandMotion220),
      curve: kOpenHandEntranceCurve,
      child: const Icon(Icons.expand_more_rounded),
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
    final shortPath = OpenHandPaths.shortenHomePath(issue.filePath);
    final (title, body) = switch (issue.kind) {
      SettingsPersistenceIssueKind.loadFailed => (
        l10n.settingsPersistenceLoadFailedTitle,
        '${l10n.settingsPersistenceLoadFailedBody}\n$shortPath',
      ),
      SettingsPersistenceIssueKind.invalidContent => (
        l10n.settingsPersistenceInvalidTitle,
        '${l10n.settingsPersistenceInvalidBody}\n$shortPath',
      ),
      SettingsPersistenceIssueKind.saveFailed => (
        l10n.settingsPersistenceSaveFailedTitle,
        '${l10n.settingsPersistenceSaveFailedBody}\n$shortPath',
      ),
    };

    return PersistenceIssueCard(
      title: title,
      body: body,
      dismissTooltip: l10n.settingsPersistenceDismiss,
      onDismiss: onDismiss,
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
    this.healthProvider,
    this.onHealthCheck,
    this.healthCheckBusy = false,
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
  final AiModelConfig? healthProvider;
  final VoidCallback? onHealthCheck;
  final bool healthCheckBusy;

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
    final effectiveOnHealthCheck = enabled ? onHealthCheck : null;
    final iconSize = compact ? 14.0 : 16.0;
    final healthActionDimension = compact ? 18.0 : 20.0;

    // 使用 Material 和 InkWell，避免 InputChip 吞掉标签内操作按钮的点击。
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
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: compact ? 180 : 280),
                child: Text(
                  modelId,
                  maxLines: 1,
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
              if (healthProvider != null) ...<Widget>[
                kOpenHandHGap4,
                AiModelHealthIndicator(
                  provider: healthProvider!,
                  modelId: modelId,
                  barCount: compact ? 10 : 16,
                  compact: compact,
                ),
                if (effectiveOnHealthCheck != null) ...<Widget>[
                  SizedBox.square(
                    dimension: healthActionDimension,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: accentColor,
                        overlayColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        surfaceTintColor: Colors.transparent,
                        elevation: 0,
                        splashFactory: NoSplash.splashFactory,
                        minimumSize: Size.zero,
                        maximumSize: Size.square(healthActionDimension),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      tooltip: openHandLocalizedText(
                        context,
                        zh: '检查模型健康状态',
                        en: 'Check model health',
                      ),
                      onPressed: effectiveOnHealthCheck,
                      icon: healthCheckBusy
                          ? const SizedBox.square(
                              dimension: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(Icons.wifi_tethering_rounded, size: iconSize),
                    ),
                  ),
                ],
              ],
              if (effectiveOnEdit != null) ...<Widget>[
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
                kOpenHandHGap2,
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
                kOpenHandHGap5,
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

class _AiProviderWebsiteLink extends StatelessWidget {
  const _AiProviderWebsiteLink({
    required this.url,
    required this.onPressed,
    required this.tooltip,
    this.style,
  });

  final String url;
  final VoidCallback onPressed;
  final String tooltip;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final linkStyle = (style ?? theme.textTheme.bodyMedium)?.copyWith(
      color: colorScheme.primary,
      fontWeight: FontWeight.w700,
      decoration: TextDecoration.underline,
      decorationColor: colorScheme.primary.withValues(alpha: 0.72),
    );
    final child = OpenHandTapRegion(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: Text(
        url,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: linkStyle,
      ),
    );
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        value: url,
        child: MicroPressFeedback(child: child),
      ),
    );
  }
}

class _AiProviderInfoChip extends StatelessWidget {
  const _AiProviderInfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chipTheme = theme.chipTheme;
    final labelStyle =
        chipTheme.labelStyle ??
        theme.textTheme.labelLarge ??
        const TextStyle(fontSize: 14);
    final fontSize = labelStyle.fontSize ?? 14;
    final textScaler = MediaQuery.textScalerOf(context);
    final scaledLineHeight =
        textScaler.scale(fontSize) * _aiProviderInfoChipLineHeight;
    final height = math.max(
      _aiProviderInfoChipMinHeight,
      scaledLineHeight + _aiProviderInfoChipVerticalPadding * 2,
    );
    final labelStrut = StrutStyle(
      fontSize: fontSize,
      height: _aiProviderInfoChipLineHeight,
      forceStrutHeight: true,
    );

    return SizedBox(
      height: height,
      child: RawChip(
        avatar: Icon(icon, size: _aiProviderInfoChipIconSize),
        avatarBoxConstraints: const BoxConstraints.tightFor(
          width: _aiProviderInfoChipIconSize,
          height: _aiProviderInfoChipIconSize,
        ),
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          strutStyle: labelStrut,
        ),
        labelStyle: labelStyle,
        padding: const EdgeInsets.symmetric(
          horizontal: _aiProviderInfoChipHorizontalPadding,
        ),
        labelPadding: const EdgeInsets.symmetric(
          horizontal: _aiProviderInfoChipLabelPadding,
        ),
        visualDensity: VisualDensity.standard,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: chipTheme.backgroundColor,
        side: chipTheme.side,
        shape: chipTheme.shape,
        iconTheme: chipTheme.iconTheme,
        clipBehavior: Clip.antiAlias,
      ),
    );
  }
}

class _AiModelTile extends StatefulWidget {
  const _AiModelTile({
    required this.model,
    required this.dragIndex,
    required this.isSelected,
    required this.isTesting,
    required this.isFirst,
    required this.isLast,
    required this.actionsEnabled,
    required this.onSelect,
    required this.onTest,
    required this.onHealthCheck,
    required this.onEdit,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onDelete,
    required this.onActiveModelChanged,
  });

  final AiModelConfig model;
  final int dragIndex;
  final bool isSelected;
  final bool isTesting;
  final bool isFirst;
  final bool isLast;
  final bool actionsEnabled;
  final VoidCallback onSelect;
  final VoidCallback onTest;
  final VoidCallback onHealthCheck;
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
  bool _modelSearchVisible = false;
  final TextEditingController _modelSearchController = TextEditingController();
  final FocusNode _modelSearchFocusNode = FocusNode();
  final Set<String> _healthCheckingModelIds = <String>{};

  /// APP 运行期间稳定的胶囊排序。冷启动后第一次构建本卡片
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
      _modelSearchVisible = false;
      _modelSearchController.clear();
      _modelSearchFocusNode.unfocus();
    } else if (widget.model.allModelIds.length <= _aiModelChipPreviewLimit) {
      _modelChipsExpanded = false;
      _modelSearchVisible = false;
      _modelSearchController.clear();
      _modelSearchFocusNode.unfocus();
    }
  }

  @override
  void dispose() {
    _modelSearchController.dispose();
    _modelSearchFocusNode.dispose();
    super.dispose();
  }

  void _toggleModelChipsExpanded() {
    HapticFeedback.selectionClick();
    setState(() {
      _modelChipsExpanded = !_modelChipsExpanded;
    });
  }

  void _toggleModelSearch() {
    HapticFeedback.selectionClick();
    final nextVisible = !_modelSearchVisible;
    setState(() {
      _modelSearchVisible = nextVisible;
      if (!nextVisible) {
        _modelSearchController.clear();
      }
    });
    if (!nextVisible) {
      _modelSearchFocusNode.unfocus();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _modelSearchVisible) {
        _modelSearchFocusNode.requestFocus();
      }
    });
  }

  Future<void> _checkModelHealth(String modelId) async {
    if (_healthCheckingModelIds.contains(modelId)) return;
    setState(() => _healthCheckingModelIds.add(modelId));
    try {
      await context.read<AiModelHealthController>().checkModel(
        widget.model,
        modelId: modelId,
      );
    } finally {
      if (mounted) setState(() => _healthCheckingModelIds.remove(modelId));
    }
  }

  Future<void> _openOfficialWebsite(String url) async {
    HapticFeedback.selectionClick();
    final launched = await openHttpUrlWithSystemBrowser(
      url,
      tag: 'settings.ai_model_provider.open_website',
    );
    if (launched || !mounted) {
      return;
    }
    showOpenHandErrorSnack(
      context,
      AppLocalizations.of(context)!.aiModelOpenWebsiteFailure,
    );
  }

  Widget _buildProviderMetaLine({
    required BuildContext context,
    required AppLocalizations l10n,
    required String modelCountLabel,
    required TextStyle? style,
  }) {
    final websiteUrl = widget.model.normalizedOfficialWebsiteUrl;
    final metaText =
        '${widget.model.protocolType.label(l10n)} · ${widget.model.authScheme.label(l10n)} · $modelCountLabel';
    if (websiteUrl.isEmpty) {
      return Text(
        metaText,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final linkMaxWidth = constraints.hasBoundedWidth
            ? math.max(0.0, constraints.maxWidth)
            : double.infinity;
        return Wrap(
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('$metaText · ', style: style),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: linkMaxWidth),
              child: _AiProviderWebsiteLink(
                url: websiteUrl,
                tooltip: l10n.aiModelOpenWebsiteTooltip,
                style: style,
                onPressed: () => _openOfficialWebsite(websiteUrl),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final healthChecking = context.select<AiModelHealthController, bool>(
      (controller) => controller.isProviderChecking(widget.model.id),
    );
    final anyHealthChecking = context.select<AiModelHealthController, bool>(
      (controller) => controller.checking,
    );
    final allModels = widget.model.allModelIds;
    final modelCountLabel = allModels.isNotEmpty
        ? l10n.aiModelCount(allModels.length)
        : openHandLocalizedText(context, zh: '无模型', en: 'No models');
    final canExpandModels = allModels.length > _aiModelChipPreviewLimit;
    final modelSearchQuery = _modelSearchVisible
        ? _modelSearchController.text.trim().toLowerCase()
        : '';
    final isSearchingModels = modelSearchQuery.isNotEmpty;
    final matchedModels = _filterAiModelIds(allModels, modelSearchQuery);
    final matchedModelIds = matchedModels.toSet();
    final matchedModelCount = matchedModels.length;
    final animationDuration = openHandMotionDuration(
      context,
      kOpenHandMotion260,
    );

    return MicroPressFeedback(
      child: InkWell(
        onTap: widget.onSelect,
        borderRadius: BorderRadius.circular(kOpenHandRadius24),
        child: AnimatedContainer(
          duration: animationDuration,
          curve: kOpenHandSwitchInCurve,
          decoration: BoxDecoration(
            color: widget.isSelected
                ? colorScheme.primaryContainer.withValues(alpha: 0.52)
                : colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(kOpenHandRadius24),
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
                          kOpenHandGap4,
                          _buildProviderMetaLine(
                            context: context,
                            l10n: l10n,
                            modelCountLabel: modelCountLabel,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (widget.model.modelId.trim().isNotEmpty) ...[
                            kOpenHandGap4,
                            Text(
                              openHandLocalizedText(
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
                    kOpenHandHGap12,
                    Wrap(
                      spacing: 4,
                      children: [
                        if (canExpandModels)
                          _AiModelSearchToggleButton(
                            visible: _modelSearchVisible,
                            enabled: widget.actionsEnabled,
                            onPressed: _toggleModelSearch,
                          ),
                        if (canExpandModels && !isSearchingModels)
                          IconButton(
                            onPressed: widget.actionsEnabled
                                ? _toggleModelChipsExpanded
                                : null,
                            tooltip: _modelChipsExpanded
                                ? openHandLocalizedText(
                                    context,
                                    zh: '折叠模型列表',
                                    en: 'Collapse model list',
                                  )
                                : openHandLocalizedText(
                                    context,
                                    zh: '展开全部模型',
                                    en: 'Show all models',
                                  ),
                            icon: AnimatedSwitcher(
                              duration: openHandMotionDuration(
                                context,
                                kOpenHandMotion220,
                              ),
                              switchInCurve: kOpenHandEntranceCurve,
                              switchOutCurve: kOpenHandSwitchOutCurve,
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
                        IgnorePointer(
                          ignoring: !widget.actionsEnabled,
                          child: ReorderableDragStartListener(
                            index: widget.dragIndex,
                            child: IconButton(
                              onPressed: () {},
                              tooltip: openHandLocalizedText(
                                context,
                                zh: '拖动排序',
                                en: 'Reorder',
                              ),
                              icon: const Icon(Icons.drag_indicator_rounded),
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
                          onPressed:
                              widget.actionsEnabled &&
                              !anyHealthChecking
                              ? widget.onHealthCheck
                              : null,
                          tooltip: openHandLocalizedText(
                            context,
                            zh: healthChecking ? '正在检查提供商健康状态' : '检查提供商健康状态',
                            en: healthChecking
                                ? 'Checking provider health'
                                : 'Check provider health',
                          ),
                          icon: OpenHandBusyStatusIcon(
                            busy: healthChecking,
                            icon: Icons.wifi_tethering_rounded,
                            size: 24,
                          ),
                        ),
                        IconButton(
                          onPressed: widget.actionsEnabled && !widget.isTesting
                              ? widget.onTest
                              : null,
                          tooltip: widget.isTesting
                              ? l10n.aiModelTesting
                              : l10n.aiModelTest,
                          icon: OpenHandBusyStatusIcon(
                            busy: widget.isTesting,
                            icon: Icons.network_check_rounded,
                            // IconButton 的图标默认按 24 绘制，转圈原本只有 18，
                            // 一忙一闲之间整个按钮会缩一下；统一到 24。
                            size: 24,
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
                    _AiProviderInfoChip(
                      icon: Icons.link_rounded,
                      label: widget.model.normalizedBaseUrl,
                    ),
                    _AiProviderInfoChip(
                      icon: widget.model.autoCompleteBaseUrl
                          ? Icons.auto_fix_high_rounded
                          : Icons.rule_rounded,
                      label: widget.model.autoCompleteBaseUrl
                          ? openHandLocalizedText(
                              context,
                              zh: '自动补全',
                              en: 'Auto-complete',
                            )
                          : openHandLocalizedText(
                              context,
                              zh: '精确 Base URL',
                              en: 'Exact Base URL',
                            ),
                    ),
                    _AiProviderInfoChip(
                      icon: Icons.vpn_key_outlined,
                      label: widget.model.maskedToken.isEmpty
                          ? l10n.aiModelNoToken
                          : widget.model.maskedToken,
                    ),
                    if (widget.model.apiDialect == AiApiDialect.openAiCompat)
                      _AiProviderInfoChip(
                        icon: Icons.route_rounded,
                        label: switch (widget.model.capabilityStatusFor(
                          AiApiFamily.responses,
                        )) {
                          'supported' => openHandLocalizedText(
                            context,
                            zh: '聊天接口 · Responses',
                            zhHant: '聊天介面 · Responses',
                            en: 'Chat API · Responses',
                          ),
                          'disabled' => openHandLocalizedText(
                            context,
                            zh: '聊天接口 · Chat Completions',
                            zhHant: '聊天介面 · Chat Completions',
                            en: 'Chat API · Chat Completions',
                          ),
                          _ => openHandLocalizedText(
                            context,
                            zh: '聊天接口 · 自动探测',
                            zhHant: '聊天介面 · 自動探測',
                            en: 'Chat API · Auto detect',
                          ),
                        },
                      ),
                    if (widget.isSelected)
                      _AiProviderInfoChip(
                        icon: Icons.check_circle_outline_rounded,
                        label: l10n.aiModelSelected,
                      ),
                  ],
                ),
                // 限制模型胶囊数量，避免卡片过高和滚动时重复构建过多控件。
                if (allModels.isNotEmpty) ...[
                  kOpenHandGap10,
                  if (canExpandModels)
                    _AnimatedSettingReveal(
                      visible: _modelSearchVisible,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _AiModelSearchField(
                          controller: _modelSearchController,
                          focusNode: _modelSearchFocusNode,
                          enabled: widget.actionsEnabled,
                          helperText: isSearchingModels
                              ? openHandLocalizedText(
                                  context,
                                  zh: '找到 $matchedModelCount / ${allModels.length} 个模型',
                                  zhHant:
                                      '找到 $matchedModelCount / ${allModels.length} 個模型',
                                  en: '$matchedModelCount of ${allModels.length} models',
                                  fr: '$matchedModelCount modèles sur ${allModels.length}',
                                  de: '$matchedModelCount von ${allModels.length} Modellen',
                                  ja: '${allModels.length} 件中 $matchedModelCount 件',
                                )
                              : null,
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ),
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
                        final filtered = isSearchingModels
                            ? ordered
                                  .where(matchedModelIds.contains)
                                  .toList(growable: false)
                            : ordered;
                        final visible =
                            isSearchingModels ||
                                _modelChipsExpanded ||
                                filtered.length <= _aiModelChipPreviewLimit
                            ? filtered
                            : filtered.sublist(0, _aiModelChipPreviewLimit);
                        final hiddenCount = ordered.length - visible.length;
                        return AnimatedSize(
                          alignment: Alignment.topLeft,
                          duration: openHandMotionDuration(
                            context,
                            kOpenHandMotion420,
                          ),
                          reverseDuration: openHandMotionDuration(
                            context,
                            kOpenHandMotion260,
                          ),
                          curve: kOpenHandEntranceCurve,
                          child: AnimatedSwitcher(
                            duration: openHandMotionDuration(
                              context,
                              kOpenHandMotion260,
                            ),
                            switchInCurve: kOpenHandEntranceCurve,
                            switchOutCurve: kOpenHandSwitchOutCurve,
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
                              key: ValueKey<String>(
                                '$isSearchingModels-$_modelChipsExpanded-$modelSearchQuery',
                              ),
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                for (final id in visible)
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _AiProviderModelChip(
                                        modelId: id,
                                        isActive: id == activeId,
                                        compact: true,
                                        enabled: widget.actionsEnabled,
                                        healthProvider: widget.model,
                                        onHealthCheck: () =>
                                            _checkModelHealth(id),
                                        healthCheckBusy: _healthCheckingModelIds
                                            .contains(id),
                                        tooltip: id == activeId
                                            ? openHandLocalizedText(
                                                ctx,
                                                zh: '当前活跃模型',
                                                en: 'Currently active model',
                                              )
                                            : openHandLocalizedText(
                                                ctx,
                                                zh: '点击切换为活跃模型',
                                                en: 'Click to set as active model',
                                              ),
                                        onPressed: id == activeId
                                            ? () {}
                                            : () => widget.onActiveModelChanged(
                                                id,
                                              ),
                                      ),
                                    ],
                                  ),
                                if (!isSearchingModels && hiddenCount > 0)
                                  _AiProviderOverflowChip(
                                    hiddenCount: hiddenCount,
                                    onPressed: _toggleModelChipsExpanded,
                                    tooltip: openHandLocalizedText(
                                      ctx,
                                      zh: '展开剩余 $hiddenCount 个模型',
                                      en: 'Show $hiddenCount more models',
                                    ),
                                  ),
                                if (visible.isEmpty)
                                  Text(
                                    openHandLocalizedText(
                                      ctx,
                                      zh: '没有匹配的模型 ID。',
                                      zhHant: '沒有符合的模型 ID。',
                                      en: 'No matching model IDs.',
                                      fr: 'Aucun ID de modèle correspondant.',
                                      de: 'Keine passende Modell-ID.',
                                      ja: '一致するモデル ID はありません。',
                                    ),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
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

class _WebEngineDispatchControls extends StatelessWidget {
  const _WebEngineDispatchControls({
    required this.featureName,
    required this.resultCountController,
    required this.defaultResultCount,
    required this.minResultCount,
    required this.maxResultCount,
    required this.onResultCountChanged,
    required this.parallel,
    required this.onParallelChanged,
    required this.parallelWorkersController,
    required this.onParallelWorkersChanged,
  });

  final String featureName;
  final TextEditingController resultCountController;
  final int defaultResultCount;
  final int minResultCount;
  final int maxResultCount;
  final ValueChanged<int> onResultCountChanged;
  final bool parallel;
  final ValueChanged<bool> onParallelChanged;
  final TextEditingController parallelWorkersController;
  final ValueChanged<int> onParallelWorkersChanged;

  /// WebSearch 与 WebFetch 的 worker 取值范围一致，直接取共用策略。
  static const int _minWorkers = AiWebEngineExecutionPolicy.minParallelWorkers;
  static const int _maxWorkers = AiWebEngineExecutionPolicy.maxParallelWorkers;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        TextField(
          controller: resultCountController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: openHandLocalizedText(
              context,
              zh: '结果数量 ($minResultCount-$maxResultCount)',
              en: 'Result Count ($minResultCount-$maxResultCount)',
            ),
            helperText: openHandLocalizedText(
              context,
              zh: '默认 $defaultResultCount，控制 $featureName 返回给模型的条目个数。',
              en:
                  'Default $defaultResultCount; caps how many $featureName '
                  'results are forwarded to the model.',
            ),
          ),
          onChanged: (value) {
            final parsed = optionalIntFromText(value);
            if (parsed == null) return;
            onResultCountChanged(
              parsed.clamp(minResultCount, maxResultCount).toInt(),
            );
          },
        ),
        kOpenHandGap14,
        Row(
          children: [
            Expanded(
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  openHandLocalizedText(
                    context,
                    zh: '并行调度引擎',
                    en: 'Parallel Engines',
                  ),
                ),
                subtitle: Text(
                  openHandLocalizedText(
                    context,
                    zh: '启用后限流并行调用多个引擎；关闭后按顺序串行调用。',
                    en:
                        'Calls engines concurrently within the worker limit; '
                        'off uses strict serial execution.',
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                value: parallel,
                onChanged: onParallelChanged,
              ),
            ),
            kOpenHandHGap12,
            SizedBox(
              width: 120,
              child: TextField(
                enabled: parallel,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                controller: parallelWorkersController,
                decoration: InputDecoration(
                  labelText: openHandLocalizedText(
                    context,
                    zh: 'Workers ($_minWorkers-$_maxWorkers)',
                    en: 'Workers ($_minWorkers-$_maxWorkers)',
                  ),
                ),
                onChanged: (value) {
                  final parsed = optionalIntFromText(value);
                  if (parsed == null) return;
                  onParallelWorkersChanged(
                    parsed.clamp(_minWorkers, _maxWorkers).toInt(),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 设置保存反馈对共享 [HighlightPulse] 的轻量适配。
class _SettingsSavePulse extends StatelessWidget {
  const _SettingsSavePulse({required this.signal});

  final ValueListenable<int> signal;

  @override
  Widget build(BuildContext context) {
    return HighlightPulse(signal: signal);
  }
}

/// 带弹性进退场动效的设置行显示/隐藏容器。
///
/// 用 [AnimatedSize]（高度弹性伸缩，easeOutBack 曲线）+ [AnimatedSwitcher]
/// （淡入淡出）组合，实现 Q 弹自然的条目显示/隐藏动效。
/// 自动遵守设置页共享 motion preference。
class _AnimatedSettingReveal extends StatelessWidget {
  const _AnimatedSettingReveal({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!_settingsMotionEnabled(context)) {
      return visible ? child : const SizedBox.shrink();
    }
    final sizeDuration = openHandMotionDuration(context, kOpenHandMotion420);
    final sizeReverseDuration = openHandMotionDuration(
      context,
      kOpenHandMotion260,
    );
    final switcherDuration = openHandMotionDuration(
      context,
      kOpenHandMotion320,
    );
    final switcherReverseDuration = openHandMotionDuration(
      context,
      kOpenHandMotion200,
    );
    return ClipRect(
      child: AnimatedSize(
        duration: sizeDuration,
        reverseDuration: sizeReverseDuration,
        curve: kOpenHandEntranceCurve,
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: switcherDuration,
          reverseDuration: switcherReverseDuration,
          switchInCurve: kOpenHandSwitchInCurve,
          switchOutCurve: kOpenHandSwitchOutCurve,
          transitionBuilder: (child, animation) {
            return AnimatedBuilder(
              animation: animation,
              builder: (context, _) {
                final raw = animation.value.clamp(0.0, 1.0);
                final slideT = kOpenHandEntranceCurve.transform(raw);
                final scaleT = kOpenHandSwitchInCurve.transform(raw);
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

// ─────────────────────────────────────────────────────────────────────────────
// WebSearch / WebFetch 引擎卡片共用外壳
// ─────────────────────────────────────────────────────────────────────────────

/// WebSearch 与 WebFetch 共用的遥测面板状态机。
mixin _ToolTelemetryPanelHost<W extends StatefulWidget, L, K, S, H>
    on State<W> {
  int? _cacheBytesOnDisk;
  bool _cacheBytesLoading = false;
  bool _cacheRefreshPending = false;
  Future<void>? _cacheRefreshTask;
  bool _clearingCache = false;
  List<L> _recentCalls = const [];
  Map<K, S> _engineStats = const {};
  Map<K, List<H>> _engineHistory = const {};
  bool _telemetryLoading = false;
  bool _telemetryRefreshPending = false;
  Future<void>? _telemetryRefreshTask;
  bool _clearingTelemetry = false;
  bool _exportingTelemetry = false;

  String get _telemetryLogTag;

  String get _telemetryToolLabel;

  String get _telemetryExportLogTag;

  String get _telemetryFileStem;

  Future<int> _loadCacheBytesOnDisk();

  Future<void> _clearCacheStore();

  String get _cacheClearContentZh;

  String get _cacheClearContentEn;

  Future<(List<L>, Map<K, S>, Map<K, List<H>>)> _loadTelemetry();

  Future<void> _clearTelemetryStore();

  Future<void> _clearEngineCooldown(K kind);

  Future<List<L>> _loadCallsForExport();

  String _callsToJson(List<L> calls);

  String _callsToCsv(List<L> calls);

  List<Widget> _buildTelemetryPanel({
    required BuildContext context,
    required String description,
    required String emptyMessage,
    required Widget Function(K kind, S stat) buildEngineRow,
    required Widget Function(L call) buildCallRow,
  }) {
    final engineRows = _engineStats.entries
        .map((entry) => buildEngineRow(entry.key, entry.value))
        .toList(growable: false);
    final callRows = _recentCalls
        .take(_maxToolTelemetryCallRows)
        .map(buildCallRow)
        .toList(growable: false);
    return <Widget>[
      ..._buildToolTelemetryHeader(
        context: context,
        description: description,
        hasData: _recentCalls.isNotEmpty || _engineStats.isNotEmpty,
        hasCalls: _recentCalls.isNotEmpty,
        loading: _telemetryLoading,
        clearing: _clearingTelemetry,
        exporting: _exportingTelemetry,
        onExportJson: () => _exportTelemetry(asCsv: false),
        onExportCsv: () => _exportTelemetry(asCsv: true),
        onRefresh: _refreshTelemetry,
        onClear: _confirmAndClearTelemetry,
      ),
      kOpenHandGap8,
      ..._buildToolTelemetryBody(
        context: context,
        loading: _telemetryLoading,
        emptyMessage: emptyMessage,
        engineRows: engineRows,
        callRows: callRows,
        totalCallCount: _recentCalls.length,
      ),
    ];
  }

  Future<void> _refreshCacheBytesOnDisk() {
    if (!mounted) return Future<void>.value();
    _cacheRefreshPending = true;
    final activeTask = _cacheRefreshTask;
    if (activeTask != null) return activeTask;
    setState(() => _cacheBytesLoading = true);
    late final Future<void> task;
    task = _drainCacheRefreshRequests().whenComplete(() {
      if (!identical(_cacheRefreshTask, task)) return;
      _cacheRefreshTask = null;
      if (mounted) setState(() => _cacheBytesLoading = false);
    });
    _cacheRefreshTask = task;
    return task;
  }

  Future<void> _drainCacheRefreshRequests() async {
    while (mounted && _cacheRefreshPending) {
      _cacheRefreshPending = false;
      var bytes = 0;
      try {
        bytes = await _loadCacheBytesOnDisk();
      } catch (e, st) {
        silentLog(_telemetryLogTag, '刷新磁盘缓存大小', e, st);
      }
      if (!mounted) return;
      if (_cacheRefreshPending) continue;
      setState(() => _cacheBytesOnDisk = bytes);
    }
  }

  Future<void> _confirmAndClearCache() async {
    if (_clearingCache) return;
    final confirmed = await _confirmClearLocalCache(
      context: context,
      toolLabel: _telemetryToolLabel,
      titleZhVerb: '清理',
      titleEnVerb: 'Clear',
      contentZh: _cacheClearContentZh,
      contentEn: _cacheClearContentEn,
    );
    if (!confirmed || !mounted) return;
    setState(() => _clearingCache = true);
    try {
      await _clearCacheStore();
    } catch (e, st) {
      silentLog(_telemetryLogTag, '清空本地缓存', e, st);
      if (mounted) {
        showOpenHandErrorSnack(
          context,
          openHandLocalizedText(
            context,
            zh: '$_telemetryToolLabel 本地缓存清理失败',
            en: 'Failed to clear $_telemetryToolLabel local cache',
          ),
        );
      }
      return;
    } finally {
      if (mounted) setState(() => _clearingCache = false);
    }
    if (!mounted) return;
    await _refreshCacheBytesOnDisk();
    if (!mounted) return;
    showOpenHandInfoSnack(
      context,
      openHandLocalizedText(
        context,
        zh: '$_telemetryToolLabel 本地缓存已清空',
        en: '$_telemetryToolLabel local cache cleared',
      ),
      duration: kOpenHandMotion1800,
    );
  }

  Widget _buildCacheActionsRow(BuildContext context) {
    return _buildToolCacheActions(
      context: context,
      bytesOnDisk: _cacheBytesOnDisk,
      loading: _cacheBytesLoading,
      clearing: _clearingCache,
      onRefresh: _refreshCacheBytesOnDisk,
      onClear: _confirmAndClearCache,
    );
  }

  Future<void> _refreshTelemetry() {
    if (!mounted) return Future<void>.value();
    _telemetryRefreshPending = true;
    final activeTask = _telemetryRefreshTask;
    if (activeTask != null) return activeTask;
    setState(() => _telemetryLoading = true);
    late final Future<void> task;
    task = _drainTelemetryRefreshRequests().whenComplete(() {
      if (!identical(_telemetryRefreshTask, task)) return;
      _telemetryRefreshTask = null;
      if (mounted) setState(() => _telemetryLoading = false);
    });
    _telemetryRefreshTask = task;
    return task;
  }

  Future<void> _drainTelemetryRefreshRequests() async {
    while (mounted && _telemetryRefreshPending) {
      _telemetryRefreshPending = false;
      try {
        final (calls, stats, history) = await _loadTelemetry();
        if (!mounted) return;
        if (_telemetryRefreshPending) continue;
        setState(() {
          _recentCalls = calls;
          _engineStats = stats;
          _engineHistory = history;
        });
      } catch (e, st) {
        silentLog(_telemetryLogTag, '刷新遥测数据', e, st);
      }
      if (!mounted) return;
    }
  }

  Future<void> _confirmAndClearTelemetry() async {
    if (_clearingTelemetry) return;
    final confirmed = await _confirmClearToolTelemetry(
      context: context,
      toolLabel: _telemetryToolLabel,
    );
    if (!confirmed || !mounted) return;
    setState(() => _clearingTelemetry = true);
    try {
      await _clearTelemetryStore();
    } catch (e, st) {
      silentLog(_telemetryLogTag, '清空遥测数据', e, st);
      if (mounted) {
        showOpenHandErrorSnack(
          context,
          openHandLocalizedText(
            context,
            zh: '$_telemetryToolLabel 遥测数据清理失败',
            en: 'Failed to clear $_telemetryToolLabel telemetry',
          ),
        );
      }
      return;
    } finally {
      if (mounted) setState(() => _clearingTelemetry = false);
    }
    if (!mounted) return;
    await _refreshTelemetry();
  }

  Future<void> _resetEngineCooldown(K kind) async {
    try {
      await _clearEngineCooldown(kind);
    } catch (e, st) {
      silentLog(_telemetryLogTag, '重置引擎冷却状态', e, st);
    }
    await _refreshTelemetry();
  }

  Future<void> _exportTelemetry({required bool asCsv}) async {
    if (_exportingTelemetry) return;
    setState(() => _exportingTelemetry = true);
    try {
      await _exportToolTelemetry<L>(
        context: context,
        logTag: _telemetryExportLogTag,
        fileStem: _telemetryFileStem,
        asCsv: asCsv,
        loadCalls: _loadCallsForExport,
        encodeJson: _callsToJson,
        encodeCsv: _callsToCsv,
      );
    } finally {
      if (mounted) setState(() => _exportingTelemetry = false);
    }
  }
}

/// 引擎卡片内的整数输入框：数字键盘 + 仅数字过滤 + 越界回落到合法区间。
Widget _buildEngineNumberField({
  required TextEditingController controller,
  required String label,
  required int fallback,
  required int min,
  required int max,
  required ValueChanged<int> onChanged,
  String? helperText,
}) {
  return TextField(
    controller: controller,
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    decoration: InputDecoration(labelText: label, helperText: helperText),
    onChanged: (text) => onChanged(
      clampedIntFromText(text, fallback: fallback, min: min, max: max),
    ),
  );
}

/// 引擎列表区：小标题 + 说明 + 可拖拽排序的引擎卡片列表。
///
/// WebSearch 与 WebFetch 的引擎列表此前各写了一份同样的标题排版与
/// ReorderableListView 配置（收缩包裹、禁用内部滚动、自绘拖拽副本）。
List<Widget> buildWebEngineListSection({
  required BuildContext context,
  required ThemeData theme,
  required ColorScheme colorScheme,
  required String title,
  required String description,
  required int itemCount,
  required void Function(int oldIndex, int newIndex) onReorder,
  required IndexedWidgetBuilder itemBuilder,
}) {
  return [
    Text(title, style: theme.textTheme.titleSmall),
    kOpenHandGap4,
    Text(
      description,
      style: theme.textTheme.bodySmall?.copyWith(
        color: colorScheme.onSurfaceVariant,
      ),
    ),
    kOpenHandGap8,
    ReorderableListView.builder(
      shrinkWrap: true,
      buildDefaultDragHandles: false,
      // 列表嵌在外层滚动区里，自身不再滚动。
      physics: const NeverScrollableScrollPhysics(),
      proxyDecorator: (child, index, animation) =>
          buildOpenHandReorderProxy(context, child, animation),
      itemCount: itemCount,
      onReorder: onReorder,
      itemBuilder: itemBuilder,
    ),
  ];
}

/// 引擎卡片的外框与头部：拖拽柄 + 标题副标题 + 可选尾标 + 展开开关 + 启用开关。
///
/// WebSearch / WebFetch 的通用引擎卡片与 WebFetch 独有的 Scrapling 运行时卡片
/// 共用这一层；后者头部多一个状态胶囊、展开区完全是另一套内容，所以只共用
/// 外壳，正文各自传入。
class _ToolEngineCardShell extends StatelessWidget {
  const _ToolEngineCardShell({
    super.key,
    required this.index,
    required this.name,
    required this.subtitle,
    required this.enabled,
    required this.onEnabledChanged,
    required this.expanded,
    required this.onExpandedChanged,
    required this.body,
    this.headerTrailing,
  });

  final int index;
  final String name;
  final String subtitle;
  final bool enabled;
  final ValueChanged<bool> onEnabledChanged;
  final bool expanded;
  final ValueChanged<bool> onExpandedChanged;

  /// 展开区内容。
  final Widget body;

  /// 排在展开开关之前的头部附加内容（如运行时状态胶囊）。
  final Widget? headerTrailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: enabled
              ? colorScheme.surfaceContainerLow
              : colorScheme.surfaceContainerLow.withValues(alpha: 0.5),
          borderRadius: kOpenHandBorderRadius12,
          border: Border.all(
            color: enabled
                ? colorScheme.primary.withValues(alpha: 0.4)
                : colorScheme.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ReorderableDragStartListener(
                    index: index,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(Icons.drag_indicator_rounded, size: 20),
                    ),
                  ),
                  kOpenHandHGap6,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: theme.textTheme.titleSmall),
                        Text(
                          subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (headerTrailing != null) ...[
                    headerTrailing!,
                    kOpenHandHGap10,
                  ],
                  IconButton(
                    tooltip: expanded
                        ? openHandCollapseLabel(context)
                        : openHandExpandLabel(context),
                    icon: _SettingsExpandIcon(expanded: expanded),
                    onPressed: () => onExpandedChanged(!expanded),
                  ),
                  Switch(value: enabled, onChanged: onEnabledChanged),
                ],
              ),
              _SettingsElasticExpansion(expanded: expanded, child: body),
            ],
          ),
        ),
      ),
    );
  }
}

/// WebSearch / WebFetch 引擎卡片共用外壳。
///
/// 两个工具的引擎卡片除「Jina 超时」「SearXNG Endpoint」这类各自独有的字段
/// 外完全一致，此前各维护一份三百余行的实现，连 API Key 眼睛按钮的尺寸约束
/// 都已分叉（一侧撑高了输入框）。这里收敛为一份：公共字段（权重 / 重试 /
/// 截断 / API Key / 复用 Provider）由外壳持有并同步控制器，各自独有的字段
/// 通过 [extrasBeforeApiKey]、[extrasAfterApiKey] 插槽注入。
class _ToolEngineCard extends StatefulWidget {
  const _ToolEngineCard({
    required super.key,
    required this.index,
    required this.name,
    required this.subtitle,
    required this.enabled,
    required this.onEnabledChanged,
    required this.weight,
    required this.minWeight,
    required this.maxWeight,
    required this.onWeightChanged,
    required this.maxRetries,
    required this.maxRetriesUpperBound,
    required this.onMaxRetriesChanged,
    required this.truncationChars,
    required this.defaultTruncationChars,
    required this.minTruncationChars,
    required this.maxTruncationChars,
    required this.onTruncationCharsChanged,
    required this.requiresApiKey,
    required this.apiKey,
    required this.onApiKeyChanged,
    required this.availableModels,
    required this.providerConfigId,
    this.apiKeyHint,
    this.onProviderConfigIdChanged,
    this.extrasBeforeApiKey = const <Widget>[],
    this.extrasAfterApiKey = const <Widget>[],
  });

  final int index;
  final String name;
  final String subtitle;

  final bool enabled;
  final ValueChanged<bool> onEnabledChanged;

  final int weight;
  final int minWeight;
  final int maxWeight;
  final ValueChanged<int> onWeightChanged;

  final int maxRetries;
  final int maxRetriesUpperBound;
  final ValueChanged<int> onMaxRetriesChanged;

  final int truncationChars;
  final int defaultTruncationChars;
  final int minTruncationChars;
  final int maxTruncationChars;
  final ValueChanged<int> onTruncationCharsChanged;

  /// 该引擎是否需要 API Key；为 false 时整段 Key 区域不渲染。
  final bool requiresApiKey;
  final String? apiKey;
  final String? apiKeyHint;

  /// 传入 null 表示用户清空了输入框。
  final ValueChanged<String?> onApiKeyChanged;

  final List<AiModelConfig> availableModels;
  final String? providerConfigId;

  /// 为 null 表示该引擎不支持复用 Provider 的 Key，下拉框不渲染。
  final ValueChanged<String?>? onProviderConfigIdChanged;

  /// 展开区内追加的引擎独有字段，分别排在 API Key 区域之前 / 之后。
  final List<Widget> extrasBeforeApiKey;
  final List<Widget> extrasAfterApiKey;

  @override
  State<_ToolEngineCard> createState() => _ToolEngineCardState();
}

class _ToolEngineCardState extends State<_ToolEngineCard> {
  late TextEditingController _apiKeyController;
  late TextEditingController _retryController;
  late TextEditingController _truncationController;
  bool _expanded = false;
  bool _apiKeyVisible = false;

  @override
  void initState() {
    super.initState();
    _apiKeyController = TextEditingController(text: widget.apiKey ?? '');
    _retryController = TextEditingController(text: '${widget.maxRetries}');
    _truncationController = TextEditingController(
      text: '${widget.truncationChars}',
    );
  }

  @override
  void didUpdateWidget(covariant _ToolEngineCard old) {
    super.didUpdateWidget(old);
    syncTextControllerText(
      _apiKeyController,
      widget.apiKey ?? '',
      previous: old.apiKey ?? '',
    );
    syncTextControllerText(
      _retryController,
      '${widget.maxRetries}',
      previous: '${old.maxRetries}',
    );
    syncTextControllerText(
      _truncationController,
      '${widget.truncationChars}',
      previous: '${old.truncationChars}',
    );
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _retryController.dispose();
    _truncationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _ToolEngineCardShell(
      index: widget.index,
      name: widget.name,
      subtitle: widget.subtitle,
      enabled: widget.enabled,
      onEnabledChanged: widget.onEnabledChanged,
      expanded: _expanded,
      onExpandedChanged: (value) => setState(() => _expanded = value),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            openHandLocalizedText(
              context,
              zh: '权重 ${widget.weight} (1 = 最低,100 = 最高;影响 summary 偏重)',
              en:
                  'Weight ${widget.weight} (higher = more emphasis in '
                  'summary)',
            ),
            style: theme.textTheme.bodySmall,
          ),
          Builder(
            builder: (context) {
              // 权重区间退化（min == max）时 Slider 的 divisions
              // 为 0 会直接断言失败，这里降级为只读展示。
              final span = widget.maxWeight - widget.minWeight;
              if (span <= 0) return const SizedBox.shrink();
              return Slider(
                min: widget.minWeight.toDouble(),
                max: widget.maxWeight.toDouble(),
                divisions: span,
                value: widget.weight.toDouble().clamp(
                  widget.minWeight.toDouble(),
                  widget.maxWeight.toDouble(),
                ),
                label: '${widget.weight}',
                onChanged: (value) => widget.onWeightChanged(value.round()),
              );
            },
          ),
          Row(
            children: [
              Expanded(
                child: _buildEngineNumberField(
                  controller: _retryController,
                  label: openHandLocalizedText(
                    context,
                    zh: '重试次数',
                    en: 'Max Retries',
                  ),
                  fallback: 0,
                  min: 0,
                  max: widget.maxRetriesUpperBound,
                  onChanged: widget.onMaxRetriesChanged,
                ),
              ),
              kOpenHandHGap12,
              Expanded(
                child: _buildEngineNumberField(
                  controller: _truncationController,
                  label: openHandLocalizedText(
                    context,
                    zh: '截断阈值 (字符)',
                    en: 'Truncation (chars)',
                  ),
                  fallback: widget.defaultTruncationChars,
                  min: widget.minTruncationChars,
                  max: widget.maxTruncationChars,
                  onChanged: widget.onTruncationCharsChanged,
                ),
              ),
            ],
          ),
          ...widget.extrasBeforeApiKey,
          if (widget.requiresApiKey) ...[
            kOpenHandGap8,
            TextField(
              controller: _apiKeyController,
              decoration: InputDecoration(
                labelText: 'API Key',
                hintText: widget.apiKeyHint,
                suffixIconConstraints: const BoxConstraints(
                  minWidth: 44,
                  minHeight: 44,
                ),
                suffixIcon: Align(
                  widthFactor: 1,
                  heightFactor: 1,
                  child: IconButton(
                    tooltip: _apiKeyVisible
                        ? openHandLocalizedText(
                            context,
                            zh: '隐藏 API Key',
                            en: 'Hide API Key',
                          )
                        : openHandLocalizedText(
                            context,
                            zh: '显示 API Key',
                            en: 'Show API Key',
                          ),
                    visualDensity: VisualDensity.compact,
                    splashRadius: 18,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 36,
                      height: 36,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      surfaceTintColor: Colors.transparent,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: Icon(
                      _apiKeyVisible
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      size: 20,
                    ),
                    onPressed: () =>
                        setState(() => _apiKeyVisible = !_apiKeyVisible),
                  ),
                ),
              ),
              obscureText: !_apiKeyVisible,
              enableSuggestions: false,
              autocorrect: false,
              onChanged: (text) => widget.onApiKeyChanged(nullIfBlank(text)),
            ),
            if (widget.onProviderConfigIdChanged != null) ...[
              kOpenHandGap8,
              AnimatedDropdownButtonFormField<String?>(
                initialValue: widget.providerConfigId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: openHandLocalizedText(
                    context,
                    zh: '复用 Provider 的 API Key (可选)',
                    en: 'Reuse Provider API Key (optional)',
                  ),
                ),
                items: [
                  DropdownMenuItem<String?>(
                    child: Text(
                      openHandLocalizedText(context, zh: '不复用', en: 'None'),
                    ),
                  ),
                  for (final model in widget.availableModels)
                    DropdownMenuItem<String?>(
                      value: model.id,
                      child: Text(
                        '${model.providerLabel} '
                        '(${model.protocolType.storageValue})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: widget.onProviderConfigIdChanged,
              ),
            ],
          ],
          ...widget.extrasAfterApiKey,
        ],
      ),
    );
  }
}

// ── 本文件内复用的文案 ──
// 同一标签在本文件里出现两次以上；抽成函数后措辞只有一个改动点。

String _settingsHelperAccessLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '连接与凭据', en: 'Access');
}

String _settingsHelperAiModelLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: 'AI 模型', en: 'AI Model');
}

String _settingsHelperAudioLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '音频编码', en: 'Audio');
}

String _settingsHelperCloneSamplePathLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '克隆样本路径', en: 'Clone Sample Path');
}

String _settingsHelperDefaultLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '默认', en: 'Default');
}

String _settingsHelperEndpointLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '接口地址', en: 'Endpoint');
}

String _settingsHelperFormatLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '音频格式', en: 'Format');
}

String _settingsHelperPitchLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '音调', en: 'Pitch');
}

String _settingsHelperRegionLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '区域 Region', en: 'Region');
}

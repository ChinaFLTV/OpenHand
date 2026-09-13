part of '../openhand_home_page.dart';

int _compareFileSystemEntitiesDirectoryFirst(
  FileSystemEntity left,
  FileSystemEntity right,
) {
  final leftIsDirectory = left is Directory;
  final rightIsDirectory = right is Directory;
  if (leftIsDirectory != rightIsDirectory) return leftIsDirectory ? -1 : 1;
  return p
      .basename(left.path)
      .toLowerCase()
      .compareTo(p.basename(right.path).toLowerCase());
}

class _ComposerDraftState {
  const _ComposerDraftState({
    required this.text,
    required this.attachments,
    this.creationRequest = AiCreationRequest.none,
  });

  final String text;
  final List<_ComposerAttachmentDraft> attachments;
  final AiCreationRequest creationRequest;
}

class _QueuedMessage {
  const _QueuedMessage({
    required this.id,
    required this.text,
    required this.attachments,
    this.creationRequest = AiCreationRequest.none,
    this.systemReminders = const <String>[],
    this.skillMetadata,
  });

  final String id;
  final String text;
  final List<_ComposerAttachmentDraft> attachments;
  final AiCreationRequest creationRequest;
  final List<String> systemReminders;
  final Map<String, Object?>? skillMetadata;
}

enum _SubmitTextOutcome { submitted, stoppedBeforeSubmit, failedBeforeSubmit }

const double _kGoalStartDialogWidth = 460;
const double _kGoalStartSwitchRowGap = 16;
const double _kGoalStartFormItemSpacing = 22;
const double _kGoalStartEnabledFieldTopPadding = 12;
const double _kGoalStartEnabledFieldBottomPadding = 4;
const Duration _kGoalStartEnabledFieldMotionDuration = Duration(
  milliseconds: 180,
);
const Curve _kGoalStartEnabledFieldMotionCurve = kOpenHandSwitchInCurve;

class _GoalStartOptionsDialog extends StatefulWidget {
  const _GoalStartOptionsDialog({
    required this.availableModels,
    required this.recentSelections,
    required this.initialModel,
  });

  final List<AiModelConfig> availableModels;
  final List<RecentModelSelection> recentSelections;
  final AiModelConfig initialModel;

  @override
  State<_GoalStartOptionsDialog> createState() =>
      _GoalStartOptionsDialogState();
}

class _GoalStartOptionsDialogState extends State<_GoalStartOptionsDialog> {
  late String _selectedProviderConfigId;
  late String _selectedModelId;
  bool _turnLimitEnabled = false;
  bool _tokenBudgetEnabled = false;
  final TextEditingController _turnLimitController = TextEditingController(
    text: '12',
  );
  final TextEditingController _tokenBudgetController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedProviderConfigId = widget.initialModel.id;
    _selectedModelId = widget.initialModel.modelId.trim().isNotEmpty
        ? widget.initialModel.modelId.trim()
        : widget.initialModel.allModelIds.firstOrNull ?? '';
  }

  @override
  void dispose() {
    _turnLimitController.dispose();
    _tokenBudgetController.dispose();
    super.dispose();
  }

  AiModelConfig? get _selectedConfig {
    return widget.availableModels
        .where((item) => item.id == _selectedProviderConfigId)
        .firstOrNull;
  }

  int? _readPositiveInt(TextEditingController controller) {
    return optionalPositiveIntFromText(controller.text);
  }

  void _submit() {
    final config = _selectedConfig;
    if (config == null || _selectedModelId.trim().isEmpty) {
      return;
    }
    final maxTurns = _turnLimitEnabled
        ? _readPositiveInt(_turnLimitController)
        : null;
    final tokenBudget = _tokenBudgetEnabled
        ? _readPositiveInt(_tokenBudgetController)
        : null;
    if ((_turnLimitEnabled && maxTurns == null) ||
        (_tokenBudgetEnabled && tokenBudget == null)) {
      return;
    }
    Navigator.of(context).pop(
      AiSessionGoalStartOptions(
        evaluatorProviderConfigId: config.id,
        evaluatorModelId: _selectedModelId.trim(),
        evaluatorModelLabel: _selectedModelId.trim(),
        maxTurns: maxTurns,
        tokenBudget: tokenBudget,
      ),
    );
  }

  Widget _buildGoalSwitchRow({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                kOpenHandGap4,
                Text(
                  subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    height: 1.28,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: _kGoalStartSwitchRowGap),
          Switch(
            value: value,
            thumbIcon: WidgetStateProperty.resolveWith<Icon?>((states) {
              if (states.contains(WidgetState.selected)) {
                return const Icon(Icons.check_rounded, size: 16);
              }
              return const Icon(Icons.close_rounded, size: 16);
            }),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final validSelection =
        _selectedConfig?.allModelIds.contains(_selectedModelId) == true;
    final invalidLimit =
        (_turnLimitEnabled && _readPositiveInt(_turnLimitController) == null) ||
        (_tokenBudgetEnabled &&
            _readPositiveInt(_tokenBudgetController) == null);
    final enabledFieldMotionDuration = openHandMotionDuration(
      context,
      _kGoalStartEnabledFieldMotionDuration,
    );
    return buildOpenHandAlertDialog(
      title: Text(
        openHandLocalizedText(context, zh: '启动目标模式', en: 'Start Goal Mode'),
        style: theme.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
      content: buildOpenHandDialogConstrainedContent(
        width: _kGoalStartDialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OpenHandModelSelectorField(
              models: widget.availableModels,
              recentSelections: widget.recentSelections,
              selectedConfigId: _selectedProviderConfigId,
              selectedModelId: _selectedModelId,
              required: true,
              labelZh: '评估模型',
              labelEn: 'Evaluator model',
              helperZh: '用于在每轮回答后验证目标是否已完成。',
              helperEn:
                  'Used after each assistant response to verify goal completion.',
              onSelected: (selection) {
                setState(() {
                  _selectedProviderConfigId = selection.$1;
                  _selectedModelId = selection.$2;
                });
              },
            ),
            const SizedBox(height: _kGoalStartFormItemSpacing),
            _buildGoalSwitchRow(
              value: _turnLimitEnabled,
              onChanged: (value) => setState(() => _turnLimitEnabled = value),
              title: openHandLocalizedText(
                context,
                zh: '轮次限制',
                en: 'Turn limit',
              ),
              subtitle: openHandLocalizedText(
                context,
                zh: '开启后限制自动推进的最大对话轮次。',
                en: 'Limit the maximum automatic conversation rounds.',
              ),
            ),
            AnimatedSize(
              duration: enabledFieldMotionDuration,
              curve: _kGoalStartEnabledFieldMotionCurve,
              alignment: Alignment.topCenter,
              child: AnimatedSwitcher(
                duration: enabledFieldMotionDuration,
                child: _turnLimitEnabled
                    ? Padding(
                        key: const ValueKey<String>('turn-limit-field'),
                        padding: const EdgeInsets.only(
                          top: _kGoalStartEnabledFieldTopPadding,
                          bottom: _kGoalStartEnabledFieldBottomPadding,
                        ),
                        child: TextField(
                          controller: _turnLimitController,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.done,
                          inputFormatters: <TextInputFormatter>[
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText: openHandLocalizedText(
                              context,
                              zh: '最大对话轮次',
                              en: 'Maximum turns',
                            ),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(
                        key: ValueKey<String>('turn-limit-empty'),
                      ),
              ),
            ),
            const SizedBox(height: _kGoalStartFormItemSpacing),
            _buildGoalSwitchRow(
              value: _tokenBudgetEnabled,
              onChanged: (value) => setState(() => _tokenBudgetEnabled = value),
              title: openHandTokenBudgetLabel(context),
              subtitle: openHandLocalizedText(
                context,
                zh: '开启后限制目标执行阶段最多消耗的 token。',
                en: 'Limit token usage while this goal runs.',
              ),
            ),
            AnimatedSize(
              duration: enabledFieldMotionDuration,
              curve: _kGoalStartEnabledFieldMotionCurve,
              alignment: Alignment.topCenter,
              child: AnimatedSwitcher(
                duration: enabledFieldMotionDuration,
                child: _tokenBudgetEnabled
                    ? Padding(
                        key: const ValueKey<String>('token-budget-field'),
                        padding: const EdgeInsets.only(
                          top: _kGoalStartEnabledFieldTopPadding,
                        ),
                        child: TextField(
                          controller: _tokenBudgetController,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.done,
                          inputFormatters: <TextInputFormatter>[
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText: openHandLocalizedText(
                              context,
                              zh: '最多消耗 token',
                              en: 'Maximum tokens',
                            ),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(
                        key: ValueKey<String>('token-budget-empty'),
                      ),
              ),
            ),
            if (!validSelection || invalidLimit) ...[
              kOpenHandGap12,
              Text(
                openHandLocalizedText(
                  context,
                  zh: '请选择可用评估模型，并填写正整数限制。',
                  en: 'Choose a valid evaluator model and enter positive limits.',
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        OpenHandDialogActionButton.secondary(
          onPressed: () => Navigator.of(context).pop(),
          label: openHandCancelLabel(context),
        ),
        OpenHandDialogActionButton.primary(
          onPressed: validSelection && !invalidLimit ? _submit : null,
          label: openHandLocalizedText(context, zh: '开始', en: 'Start'),
        ),
      ],
    );
  }
}

class _TitleSummaryDialogResult {
  const _TitleSummaryDialogResult({
    required this.startIndex,
    required this.endIndex,
    required this.model,
  });

  final int startIndex;
  final int endIndex;
  final AiModelConfig? model;
}

const double _kTitleProgressDialogWidth = 360;

/// 标题摘要消息区间与模型选择弹窗。
class _TitleSummaryRangeDialog extends StatefulWidget {
  const _TitleSummaryRangeDialog({
    required this.userMessages,
    required this.availableModels,
    required this.recentModelSelections,
    required this.initialModel,
  });

  final List<AiSessionMessage> userMessages;
  final List<AiModelConfig> availableModels;
  final List<RecentModelSelection> recentModelSelections;
  final AiModelConfig? initialModel;

  @override
  State<_TitleSummaryRangeDialog> createState() =>
      _TitleSummaryRangeDialogState();
}

class _TitleSummaryRangeDialogState extends State<_TitleSummaryRangeDialog> {
  late int _startIdx = 0;
  late int _endIdx = (widget.userMessages.length - 1).clamp(0, 2);
  late String? _selectedConfigId = widget.initialModel?.id;
  late String? _selectedModelId = widget.initialModel?.modelId;

  AiModelConfig? get _selectedModel {
    final configId = _selectedConfigId?.trim();
    final modelId = _selectedModelId?.trim();
    if (configId == null ||
        configId.isEmpty ||
        modelId == null ||
        modelId.isEmpty) {
      return null;
    }
    for (final config in widget.availableModels) {
      if (config.id != configId) continue;
      if (!config.allModelIds.contains(modelId)) return null;
      return config.modelId == modelId
          ? config
          : config.copyWith(modelId: modelId);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final total = widget.userMessages.length;
    final selectedCount = total < 1
        ? 0
        : (_endIdx - _startIdx + 1).clamp(1, total);
    final selectedCountLabel = openHandLocalizedText(
      context,
      zh: '已选择 $selectedCount 条用户消息',
      zhHant: '已選擇 $selectedCount 則使用者訊息',
      en: 'Selected $selectedCount user messages',
      fr: '$selectedCount messages utilisateur sélectionnés',
      de: '$selectedCount Nutzernachrichten ausgewählt',
      ja: '$selectedCount 件のユーザーメッセージを選択済み',
    );

    String previewLabel(int idx, {int maxLength = 42}) {
      if (idx < 0 || idx >= total) return '#${idx + 1}';
      final content = collapseInlineWhitespace(
        widget.userMessages[idx].content,
      );
      final preview = clipTextWithEllipsis(content, maxLength);
      return preview.isEmpty ? '#${idx + 1}' : preview;
    }

    return OpenHandEditorDialogScaffold(
      title: openHandGenerateAiTitleLabel(context),
      subtitle: selectedCountLabel,
      icon: Icons.title_rounded,
      iconColor: colorScheme.primary,
      maxWidth: kOpenHandDialogWidthCompact,
      maxHeight: kOpenHandDialogHeightCompact,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OpenHandDialogSectionCard(
            icon: Icons.smart_toy_outlined,
            accent: colorScheme.primary,
            title: openHandModelLabel(context),
            child: OpenHandModelSelectorField(
              models: widget.availableModels,
              recentSelections: widget.recentModelSelections,
              selectedConfigId: _selectedConfigId,
              selectedModelId: _selectedModelId,
              labelZh: '标题生成模型',
              labelEn: 'Title Model',
              helperZh: '未手动调整时，按当前线程模型、同提供商默认标题模型、全局默认标题模型依次选择。',
              helperEn:
                  'Defaults to the thread model, provider title fallback, then the global title model.',
              onSelected: (selection) {
                setState(() {
                  _selectedConfigId = selection.$1;
                  _selectedModelId = selection.$2;
                });
              },
            ),
          ),
          kOpenHandGap14,
          OpenHandDialogSectionCard(
            icon: Icons.linear_scale_rounded,
            accent: OpenHandStatusColors.info,
            title: openHandLocalizedText(
              context,
              zh: '消息范围',
              zhHant: '訊息範圍',
              en: 'Message Range',
              fr: 'Plage de messages',
              de: 'Nachrichtenbereich',
              ja: 'メッセージ範囲',
            ),
            subtitle: selectedCountLabel,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OpenHandRangeEndpointPair(
                  start: OpenHandRangeEndpointCard(
                    icon: Icons.tag_rounded,
                    label: openHandLocalizedText(
                      context,
                      zh: '起始',
                      zhHant: '起始',
                      en: 'From',
                      fr: 'Début',
                      de: 'Von',
                      ja: '開始',
                    ),
                    indexLabel: '#${_startIdx + 1}',
                    preview: previewLabel(_startIdx),
                    accent: colorScheme.primary,
                  ),
                  end: OpenHandRangeEndpointCard(
                    icon: Icons.tag_rounded,
                    label: openHandLocalizedText(
                      context,
                      zh: '结束',
                      zhHant: '結束',
                      en: 'To',
                      fr: 'Fin',
                      de: 'Bis',
                      ja: '終了',
                    ),
                    indexLabel: '#${_endIdx + 1}',
                    preview: previewLabel(_endIdx),
                    accent: OpenHandStatusColors.success,
                  ),
                ),
                if (total > 1) ...[
                  kOpenHandGap8,
                  RangeSlider(
                    values: RangeValues(
                      _startIdx.toDouble(),
                      _endIdx.toDouble(),
                    ),
                    max: (total - 1).toDouble(),
                    divisions: total - 1,
                    labels: RangeLabels('#${_startIdx + 1}', '#${_endIdx + 1}'),
                    onChanged: (values) {
                      setState(() {
                        _startIdx = values.start.round();
                        _endIdx = values.end.round();
                      });
                    },
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      actions: [
        OpenHandDialogActionButton.secondary(
          onPressed: () => Navigator.of(context).pop(),
          label: AppLocalizations.of(context)!.commonCancel,
        ),
        OpenHandDialogActionButton.primary(
          onPressed: total < 1
              ? null
              : () => Navigator.of(context).pop(
                  _TitleSummaryDialogResult(
                    startIndex: _startIdx,
                    endIndex: _endIdx,
                    model: _selectedModel,
                  ),
                ),
          label: openHandLocalizedText(
            context,
            zh: '生成标题',
            zhHant: '產生標題',
            en: 'Generate',
            fr: 'Générer',
            de: 'Erstellen',
            ja: '生成',
          ),
        ),
      ],
    );
  }
}

class _TitleGenerationProgressDialog extends StatelessWidget {
  const _TitleGenerationProgressDialog({required this.onCancel});

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return PopScope(
      canPop: false,
      child: buildOpenHandAlertDialog(
        title: Text(
          openHandGenerateAiTitleLabel(context),
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
        content: buildOpenHandDialogConstrainedContent(
          width: _kTitleProgressDialogWidth,
          child: Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: colorScheme.primary,
                ),
              ),
              kOpenHandHGap14,
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      openHandLocalizedText(
                        context,
                        zh: '正在生成摘要标题...',
                        zhHant: '正在產生摘要標題...',
                        en: 'Generating title...',
                        fr: 'Génération du titre...',
                        de: 'Titel wird erstellt...',
                        ja: 'タイトルを生成中...',
                      ),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    kOpenHandGap3,
                    Text(
                      openHandLocalizedText(
                        context,
                        zh: '完成后会自动更新线程标题。',
                        zhHant: '完成後會自動更新執行緒標題。',
                        en: 'The thread title updates automatically.',
                        fr: 'Le titre du fil sera mis à jour automatiquement.',
                        de: 'Der Thread-Titel wird automatisch aktualisiert.',
                        ja: '完了後、スレッドのタイトルは自動更新されます。',
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          OpenHandDialogActionButton.secondary(
            onPressed: onCancel,
            icon: Icons.close_rounded,
            label: AppLocalizations.of(context)!.commonCancel,
          ),
        ],
      ),
    );
  }
}

/// 编辑当前生成模式的 [AiCreationOptions]；用户取消时返回空值。
class _CreationOptionsDialog extends StatefulWidget {
  const _CreationOptionsDialog({
    required this.mode,
    required this.initial,
    this.selectedModel,
  });

  final _CreationMode mode;
  final AiCreationOptions initial;
  final AiModelConfig? selectedModel;

  @override
  State<_CreationOptionsDialog> createState() => _CreationOptionsDialogState();
}

class _CreationOptionsDialogState extends State<_CreationOptionsDialog> {
  late String? _aspectRatio = widget.initial.aspectRatio;
  late String? _size = widget.initial.size;
  late int? _duration = widget.initial.durationSeconds;
  late int _count = widget.initial.count;
  late String? _quality = widget.initial.quality;
  late String? _style = widget.initial.style;
  late String? _outputFormat = _initialOutputFormat();
  late String? _background = widget.initial.background;
  late bool? _promptEnhance = widget.initial.promptEnhance;
  late bool? _watermark = widget.initial.watermark;
  late String? _resolution = widget.initial.resolution;
  late int? _frameRate = widget.initial.frameRate;
  late int? _numFrames = widget.initial.numFrames;
  late String? _mode = widget.initial.mode;
  late double? _speed = widget.initial.speed;
  late int? _sampleRate = widget.initial.sampleRate;
  late int? _bitrate = _initialAudioBitrate();
  late double? _volume = widget.initial.volume;
  late double? _pitch = widget.initial.pitch;
  late bool _omitVoice = widget.initial.omitVoice;
  late bool _customVoiceInputVisible = _initialUsesCustomVoice();
  late final TextEditingController _negativePromptController =
      TextEditingController(text: widget.initial.negativePrompt ?? '');
  late final TextEditingController _seedController = TextEditingController(
    text: widget.initial.seed?.toString() ?? '',
  );
  late final TextEditingController _voiceController = TextEditingController(
    text: _initialAudioVoice(),
  );

  // 图片使用 1024 基准像素尺寸；视频只保留宽高比，实际尺寸由服务商决定。
  static const List<({String ratio, String size})> _imageRatios = [
    (ratio: '1:1', size: '1024x1024'),
    (ratio: '16:9', size: '1792x1024'),
    (ratio: '9:16', size: '1024x1792'),
    (ratio: '4:3', size: '1280x960'),
    (ratio: '3:4', size: '960x1280'),
  ];

  static const List<String> _videoRatios = ['16:9', '9:16', '1:1', '4:3'];
  static const List<int> _videoDurations = [3, 5, 8, 10];
  static const List<int> _audioDurations = [5, 10, 20, 30, 60];
  static const List<String> _imageQualities = [
    'auto',
    'standard',
    'hd',
    'high',
  ];
  static const List<String> _imageStyles = ['natural', 'vivid'];
  static const List<String> _imageFormats = ['png', 'jpeg', 'webp'];
  static const List<String> _imageBackgrounds = [
    'auto',
    'transparent',
    'opaque',
  ];
  static const List<String> _videoResolutions = ['480p', '720p', '1080p'];
  static const List<int> _videoFrameRates = [16, 24, 30, 60];
  static const List<int> _videoFrames = [81, 121, 161, 241, 441];
  static const List<String> _videoModes = ['keyframes'];
  static const List<String> _audioFormats = [
    'mp3',
    'wav',
    'opus',
    'aac',
    'flac',
    'pcm',
  ];
  static const List<double> _audioSpeeds = [0.75, 1.0, 1.25, 1.5];
  static const List<int> _audioSampleRates = [16000, 24000, 32000, 44100];
  static const List<int> _audioBitrates = [64000, 128000, 192000, 256000];
  static const List<double> _audioVolumes = [0.8, 1.0, 1.2];
  static const List<double> _audioPitches = [-2.0, 0.0, 2.0];
  static const int _minCreationCount = 1;
  static const int _maxCreationCount = 4;

  @override
  void dispose() {
    _negativePromptController.dispose();
    _seedController.dispose();
    _voiceController.dispose();
    super.dispose();
  }

  String? get _audioModelId {
    final model = widget.selectedModel;
    if (model == null) return null;
    final routed = model
        .resolveOperationModelId(AiApiFamily.audioSpeech)
        .trim();
    return routed.isNotEmpty ? routed : model.modelId.trim();
  }

  List<AiTtsCatalogOption> get _audioVoiceOptions {
    final model = widget.selectedModel;
    final modelId = _audioModelId;
    if (model == null || modelId == null || modelId.isEmpty) {
      return const <AiTtsCatalogOption>[];
    }
    return AiTtsProviderCatalogs.voiceOptionsForAiModel(
      protocol: model.protocolType,
      modelId: modelId,
    );
  }

  List<AiTtsCatalogOption> get _audioFormatOptions {
    final model = widget.selectedModel;
    final modelId = _audioModelId;
    if (model == null || modelId == null || modelId.isEmpty) {
      return [
        for (final format in _audioFormats) AiTtsCatalogOption(format, format),
      ];
    }
    return AiTtsProviderCatalogs.formatOptionsForAiModel(
      protocol: model.protocolType,
      modelId: modelId,
    );
  }

  List<String> get _audioFormatValues {
    return trimmedNonEmptyStrings(
      _audioFormatOptions.map((option) => option.value),
    );
  }

  String _audioFormatLabel(String value) {
    final normalized = value.trim();
    for (final option in _audioFormatOptions) {
      if (option.value == normalized) {
        return _audioCatalogOptionLabel(option);
      }
    }
    return normalized;
  }

  String _audioCatalogOptionLabel(AiTtsCatalogOption option) {
    final english = option.enLabel?.trim();
    final fallback = english == null || english.isEmpty
        ? option.label
        : english;
    return openHandLocalizedText(
      context,
      zh: option.label,
      zhHant: option.label,
      en: fallback,
      fr: fallback,
      de: fallback,
      ja: fallback,
    );
  }

  String? _initialOutputFormat() {
    final raw = widget.initial.outputFormat?.trim();
    if (widget.mode != _CreationMode.audio || raw == null || raw.isEmpty) {
      return raw;
    }
    final options = _audioFormatValues;
    if (options.isEmpty || options.contains(raw)) return raw;
    return null;
  }

  String _initialAudioVoice() {
    if (widget.initial.omitVoice) return '';
    final raw = widget.initial.voice?.trim() ?? '';
    final model = widget.selectedModel;
    final modelId = _audioModelId;
    final options = _audioVoiceOptions;
    if (model == null || modelId == null || modelId.isEmpty) return raw;
    if (raw.isNotEmpty) {
      if (_voiceInCatalog(raw, options)) return raw;
      final closedCatalog =
          AiTtsProviderCatalogs.usesStepFunSpeech(
            protocol: model.protocolType,
            modelId: modelId,
          ) ||
          AiTtsProviderCatalogs.usesQwenSpeech(
            protocol: model.protocolType,
            modelId: modelId,
          );
      if (!closedCatalog) return raw;
    }
    if (options.isEmpty) return raw;
    final fallback = AiTtsProviderCatalogs.defaultVoiceForAiModel(
      protocol: model.protocolType,
      modelId: modelId,
    );
    if (_voiceInCatalog(fallback, options)) return fallback;
    return options.first.value;
  }

  bool _initialUsesCustomVoice() {
    if (widget.initial.omitVoice) return false;
    final voice = _initialAudioVoice();
    final options = _audioVoiceOptions;
    return voice.isNotEmpty &&
        options.isNotEmpty &&
        !_voiceInCatalog(voice, options);
  }

  bool _voiceInCatalog(String voice, List<AiTtsCatalogOption> options) {
    final normalized = voice.trim();
    if (normalized.isEmpty) return false;
    return options.any((option) => option.value == normalized);
  }

  List<int> get _audioBitrateValues {
    final modelId = _audioModelId;
    if (modelId != null && AiTtsProviderCatalogs.isMiniMaxMusicModel(modelId)) {
      return const <int>[32000, 64000, 128000, 256000];
    }
    return _audioBitrates;
  }

  int? _initialAudioBitrate() {
    final bitrate = widget.initial.bitrate;
    if (widget.mode != _CreationMode.audio || bitrate == null) return bitrate;
    return _audioBitrateValues.contains(bitrate) ? bitrate : null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final isImage = widget.mode == _CreationMode.image;
    final isVideo = widget.mode == _CreationMode.video;
    final isAudio = widget.mode == _CreationMode.audio;
    final (title, subtitle, icon) = switch (widget.mode) {
      _CreationMode.image => (
        l10n.creationOptionsImageTitle,
        l10n.creationOptionsImageSubtitle,
        Icons.image_outlined,
      ),
      _CreationMode.video => (
        l10n.creationOptionsVideoTitle,
        l10n.creationOptionsVideoSubtitle,
        Icons.videocam_outlined,
      ),
      _CreationMode.audio => (
        l10n.creationOptionsAudioTitle,
        l10n.creationOptionsAudioSubtitle,
        Icons.graphic_eq_rounded,
      ),
      _ => (
        l10n.creationOptionsImageTitle,
        l10n.creationOptionsImageSubtitle,
        Icons.tune_rounded,
      ),
    };
    return OpenHandEditorDialogScaffold(
      title: title,
      subtitle: subtitle,
      icon: icon,
      maxWidth: kOpenHandDialogWidthStandard,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isImage || isVideo) ...[
            OpenHandDialogSectionCard(
              icon: Icons.crop_free_rounded,
              accent: colorScheme.primary,
              title: l10n.creationOptionsSectionFrame,
              subtitle: l10n.creationOptionsSectionFrameHint,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _fieldLabel(context, l10n.creationOptionsAspectRatio),
                  kOpenHandGap8,
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (isImage)
                        for (final preset in _imageRatios)
                          _optionChip(
                            label: Text(preset.ratio),
                            selected: _aspectRatio == preset.ratio,
                            onSelected: () => setState(() {
                              _aspectRatio = preset.ratio;
                              _size = preset.size;
                            }),
                          ),
                      if (isVideo)
                        for (final ratio in _videoRatios)
                          _optionChip(
                            label: Text(ratio),
                            selected: _aspectRatio == ratio,
                            onSelected: () =>
                                setState(() => _aspectRatio = ratio),
                          ),
                    ],
                  ),
                  if (isVideo) ...[
                    kOpenHandGap14,
                    _choiceSection<String>(
                      context: context,
                      title: l10n.creationOptionsResolution,
                      values: _videoResolutions,
                      selected: _resolution,
                      labelFor: (value) => value,
                      onSelected: (value) =>
                          setState(() => _resolution = value),
                    ),
                  ],
                  if (isImage) ...[
                    kOpenHandGap14,
                    _choiceSection<String>(
                      context: context,
                      title: l10n.creationOptionsQuality,
                      values: _imageQualities,
                      selected: _quality,
                      labelFor: (value) => _creationQualityLabel(l10n, value),
                      onSelected: (value) => setState(() => _quality = value),
                    ),
                    kOpenHandGap14,
                    _choiceSection<String>(
                      context: context,
                      title: l10n.creationOptionsStyle,
                      values: _imageStyles,
                      selected: _style,
                      labelFor: (value) => _creationStyleLabel(l10n, value),
                      onSelected: (value) => setState(() => _style = value),
                    ),
                    kOpenHandGap14,
                    _choiceSection<String>(
                      context: context,
                      title: l10n.creationOptionsOutputFormat,
                      values: _imageFormats,
                      selected: _outputFormat,
                      labelFor: (value) => value,
                      onSelected: (value) =>
                          setState(() => _outputFormat = value),
                    ),
                    kOpenHandGap14,
                    _choiceSection<String>(
                      context: context,
                      title: l10n.creationOptionsBackground,
                      values: _imageBackgrounds,
                      selected: _background,
                      labelFor: (value) =>
                          _creationBackgroundLabel(l10n, value),
                      onSelected: (value) =>
                          setState(() => _background = value),
                    ),
                  ],
                ],
              ),
            ),
            kOpenHandGap12,
          ],
          if (isVideo)
            OpenHandDialogSectionCard(
              icon: Icons.motion_photos_on_outlined,
              accent: colorScheme.tertiary,
              title: l10n.creationOptionsSectionMotion,
              subtitle: l10n.creationOptionsSectionMotionHint,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _fieldLabel(context, l10n.creationOptionsDuration),
                  kOpenHandGap8,
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final duration in _videoDurations)
                        _optionChip(
                          label: Text(
                            l10n.creationOptionsDurationSeconds(duration),
                          ),
                          selected: _duration == duration,
                          onSelected: () =>
                              setState(() => _duration = duration),
                        ),
                    ],
                  ),
                  kOpenHandGap14,
                  _choiceSection<int>(
                    context: context,
                    title: l10n.creationOptionsFrameRate,
                    values: _videoFrameRates,
                    selected: _frameRate,
                    labelFor: l10n.creationOptionsFrameRateFps,
                    onSelected: (value) => setState(() => _frameRate = value),
                  ),
                  kOpenHandGap14,
                  _choiceSection<int>(
                    context: context,
                    title: l10n.creationOptionsFrames,
                    values: _videoFrames,
                    selected: _numFrames,
                    labelFor: (value) => '$value',
                    onSelected: (value) => setState(() => _numFrames = value),
                  ),
                  kOpenHandGap14,
                  _choiceSection<String>(
                    context: context,
                    title: l10n.creationOptionsMode,
                    values: _videoModes,
                    selected: _mode,
                    labelFor: (value) => _creationVideoModeLabel(l10n, value),
                    onSelected: (value) => setState(() => _mode = value),
                  ),
                ],
              ),
            ),
          if (isVideo) kOpenHandGap12,
          if (isImage || isVideo) ...[
            OpenHandDialogSectionCard(
              icon: Icons.auto_awesome_rounded,
              accent: OpenHandStatusColors.warning,
              title: l10n.creationOptionsSectionGenerate,
              subtitle: l10n.creationOptionsSectionGenerateHint,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _triBoolSection(
                    context: context,
                    title: l10n.creationOptionsPromptEnhance,
                    value: _promptEnhance,
                    onChanged: (value) =>
                        setState(() => _promptEnhance = value),
                  ),
                  kOpenHandGap14,
                  _triBoolSection(
                    context: context,
                    title: l10n.creationOptionsWatermark,
                    value: _watermark,
                    onChanged: (value) => setState(() => _watermark = value),
                  ),
                  kOpenHandGap14,
                  _textInput(
                    context,
                    label: l10n.creationOptionsNegativePrompt,
                    controller: _negativePromptController,
                    maxLines: 2,
                  ),
                  kOpenHandGap12,
                  _textInput(
                    context,
                    label: l10n.creationOptionsSeed,
                    controller: _seedController,
                    keyboardType: TextInputType.number,
                  ),
                ],
              ),
            ),
            kOpenHandGap12,
          ],
          if (isAudio) ...[
            OpenHandDialogSectionCard(
              icon: Icons.record_voice_over_outlined,
              accent: OpenHandStatusColors.success,
              title: l10n.creationOptionsSectionSound,
              subtitle: l10n.creationOptionsSectionSoundHint,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _audioVoiceSection(context),
                  kOpenHandGap14,
                  _fieldLabel(context, l10n.creationOptionsDuration),
                  kOpenHandGap8,
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final duration in _audioDurations)
                        _optionChip(
                          label: Text(
                            l10n.creationOptionsDurationSeconds(duration),
                          ),
                          selected: _duration == duration,
                          onSelected: () =>
                              setState(() => _duration = duration),
                        ),
                    ],
                  ),
                  kOpenHandGap14,
                  _choiceSection<double>(
                    context: context,
                    title: l10n.creationOptionsSpeed,
                    values: _audioSpeeds,
                    selected: _speed,
                    labelFor: (value) => _creationMultiplierLabel(l10n, value),
                    onSelected: (value) => setState(() => _speed = value),
                  ),
                  kOpenHandGap14,
                  _choiceSection<double>(
                    context: context,
                    title: l10n.creationOptionsVolume,
                    values: _audioVolumes,
                    selected: _volume,
                    labelFor: (value) => _creationMultiplierLabel(l10n, value),
                    onSelected: (value) => setState(() => _volume = value),
                  ),
                  kOpenHandGap14,
                  _choiceSection<double>(
                    context: context,
                    title: l10n.creationOptionsPitch,
                    values: _audioPitches,
                    selected: _pitch,
                    labelFor: (value) => value.toStringAsFixed(0),
                    onSelected: (value) => setState(() => _pitch = value),
                  ),
                ],
              ),
            ),
            kOpenHandGap12,
            OpenHandDialogSectionCard(
              icon: Icons.tune_rounded,
              accent: OpenHandStatusColors.info,
              title: l10n.creationOptionsSectionEncode,
              subtitle: l10n.creationOptionsSectionEncodeHint,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _choiceSection<String>(
                    context: context,
                    title: l10n.creationOptionsAudioFormat,
                    values: _audioFormatValues,
                    selected: _outputFormat,
                    labelFor: _audioFormatLabel,
                    onSelected: (value) =>
                        setState(() => _outputFormat = value),
                  ),
                  kOpenHandGap14,
                  _choiceSection<int>(
                    context: context,
                    title: l10n.creationOptionsSampleRate,
                    values: _audioSampleRates,
                    selected: _sampleRate,
                    labelFor: (value) => '$value',
                    onSelected: (value) => setState(() => _sampleRate = value),
                  ),
                  kOpenHandGap14,
                  _choiceSection<int>(
                    context: context,
                    title: l10n.creationOptionsBitrate,
                    values: _audioBitrateValues,
                    selected: _bitrate,
                    labelFor: (value) =>
                        l10n.creationOptionsBitrateKbps(value ~/ 1000),
                    onSelected: (value) => setState(() => _bitrate = value),
                  ),
                ],
              ),
            ),
            kOpenHandGap12,
          ],
          OpenHandDialogSectionCard(
            icon: Icons.filter_none_rounded,
            accent: OpenHandStatusColors.caution,
            title: l10n.creationOptionsSectionCount,
            subtitle: l10n.creationOptionsSectionCountHint,
            child: _countControl(context),
          ),
        ],
      ),
      actions: [
        OpenHandDialogActionButton.secondary(
          onPressed: () => Navigator.of(context).pop(),
          label: l10n.commonCancel,
        ),
        OpenHandDialogActionButton.primary(
          onPressed: () => Navigator.of(context).pop(_selectedOptions()),
          label: l10n.commonConfirm,
        ),
      ],
    );
  }

  Widget _fieldLabel(BuildContext context, String label) {
    final theme = Theme.of(context);
    return Text(
      label,
      style: theme.textTheme.labelLarge?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _optionChip({
    required Widget label,
    required bool selected,
    required VoidCallback onSelected,
  }) {
    return OpenHandChoicePill(
      selected: selected,
      onSelected: onSelected,
      child: label,
    );
  }

  Widget _choiceSection<T>({
    required BuildContext context,
    required String title,
    required List<T> values,
    required T? selected,
    required String Function(T value) labelFor,
    required ValueChanged<T?> onSelected,
  }) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _fieldLabel(context, title),
        kOpenHandGap8,
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _optionChip(
              label: Text(l10n.creationOptionsAuto),
              selected: selected == null,
              onSelected: () => onSelected(null),
            ),
            for (final value in values)
              _optionChip(
                label: Text(labelFor(value)),
                selected: selected == value,
                onSelected: () => onSelected(value),
              ),
          ],
        ),
      ],
    );
  }

  Widget _triBoolSection({
    required BuildContext context,
    required String title,
    required bool? value,
    required ValueChanged<bool?> onChanged,
  }) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _fieldLabel(context, title),
        kOpenHandGap8,
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _optionChip(
              label: Text(l10n.creationOptionsAuto),
              selected: value == null,
              onSelected: () => onChanged(null),
            ),
            _optionChip(
              label: Text(l10n.creationOptionsOn),
              selected: value == true,
              onSelected: () => onChanged(true),
            ),
            _optionChip(
              label: Text(l10n.creationOptionsOff),
              selected: value == false,
              onSelected: () => onChanged(false),
            ),
          ],
        ),
      ],
    );
  }

  Widget _audioVoiceSection(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final options = _audioVoiceOptions;
    final currentVoice = _voiceController.text.trim();
    final selectedKnown = _voiceInCatalog(currentVoice, options);
    final customSelected =
        !_omitVoice && _customVoiceInputVisible && !selectedKnown;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _fieldLabel(context, l10n.creationOptionsVoice),
        kOpenHandGap8,
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _optionChip(
              label: Text(l10n.creationOptionsVoiceUnspecified),
              selected: _omitVoice,
              onSelected: _selectNoAudioVoice,
            ),
            for (final option in options)
              _optionChip(
                label: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: Text(
                    _audioCatalogOptionLabel(option),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                selected: !_omitVoice && currentVoice == option.value,
                onSelected: () => _selectAudioVoice(option.value),
              ),
            _optionChip(
              label: Text(l10n.creationOptionsCustomVoice),
              selected: customSelected,
              onSelected: () => _showCustomVoiceInput(selectedKnown),
            ),
          ],
        ),
        OpenHandVerticalRevealSwitcher(
          duration: kOpenHandDialogValidationRevealDuration,
          child: _customVoiceInputVisible
              ? Padding(
                  key: const ValueKey<String>('custom-audio-voice'),
                  padding: const EdgeInsets.only(top: 12),
                  child: _textInput(
                    context,
                    label: l10n.creationOptionsCustomVoiceId,
                    controller: _voiceController,
                  ),
                )
              : const SizedBox(key: ValueKey<String>('preset-audio-voice')),
        ),
      ],
    );
  }

  void _selectAudioVoice(String voice) {
    setState(() {
      _omitVoice = false;
      _customVoiceInputVisible = false;
      _voiceController.text = voice;
    });
  }

  void _selectNoAudioVoice() {
    setState(() {
      _omitVoice = true;
      _customVoiceInputVisible = false;
      _voiceController.clear();
    });
  }

  void _showCustomVoiceInput(bool clearKnownVoice) {
    setState(() {
      _omitVoice = false;
      _customVoiceInputVisible = true;
      if (clearKnownVoice) _voiceController.clear();
    });
  }

  Widget _textInput(
    BuildContext context, {
    required String label,
    required TextEditingController controller,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        border: const OutlineInputBorder(borderRadius: kOpenHandBorderRadius16),
      ),
    );
  }

  Widget _countControl(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final canDecrease = _count > _minCreationCount;
    final canIncrease = _count < _maxCreationCount;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          colorScheme.primary.withValues(alpha: 0.10),
          colorScheme.surfaceContainerLow,
        ),
        borderRadius: kOpenHandPillBorderRadius,
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          MicroPressFeedback(
            enabled: canDecrease,
            child: IconButton(
              onPressed: canDecrease ? () => setState(() => _count--) : null,
              icon: const Icon(Icons.remove_rounded),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '$_count',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          MicroPressFeedback(
            enabled: canIncrease,
            child: IconButton(
              onPressed: canIncrease ? () => setState(() => _count++) : null,
              icon: const Icon(Icons.add_rounded),
            ),
          ),
        ],
      ),
    );
  }

  AiCreationOptions _selectedOptions() {
    final isImage = widget.mode == _CreationMode.image;
    final isVideo = widget.mode == _CreationMode.video;
    final isAudio = widget.mode == _CreationMode.audio;
    final negativePrompt = _trimmedOrNull(_negativePromptController.text);
    final voice = _selectedAudioVoiceOrNull();
    return AiCreationOptions(
      size: isImage ? _size : null,
      aspectRatio: isAudio ? null : _aspectRatio,
      durationSeconds: isImage ? null : _duration,
      count: _count,
      quality: isImage ? _quality : null,
      style: isImage ? _style : null,
      outputFormat: (isImage || isAudio) ? _outputFormat : null,
      background: isImage ? _background : null,
      negativePrompt: (isImage || isVideo) ? negativePrompt : null,
      promptEnhance: (isImage || isVideo) ? _promptEnhance : null,
      watermark: (isImage || isVideo) ? _watermark : null,
      seed: (isImage || isVideo)
          ? optionalPositiveIntFromText(_seedController.text)
          : null,
      resolution: isVideo ? _resolution : null,
      frameRate: isVideo ? _frameRate : null,
      numFrames: isVideo ? _numFrames : null,
      mode: isVideo ? _mode : null,
      voice: isAudio ? voice : null,
      omitVoice: isAudio && _omitVoice,
      speed: isAudio ? _speed : null,
      sampleRate: isAudio ? _sampleRate : null,
      bitrate: isAudio ? _bitrate : null,
      volume: isAudio ? _volume : null,
      pitch: isAudio ? _pitch : null,
    );
  }

  String? _selectedAudioVoiceOrNull() {
    if (widget.mode != _CreationMode.audio) return null;
    if (_omitVoice) return null;
    final raw = _trimmedOrNull(_voiceController.text);
    if (raw == null) return null;
    final model = widget.selectedModel;
    final modelId = _audioModelId;
    if (model == null || modelId == null || modelId.isEmpty) return raw;
    if (_customVoiceInputVisible && !_voiceInCatalog(raw, _audioVoiceOptions)) {
      return raw;
    }
    return AiTtsProviderCatalogs.normalizeVoiceForAiModel(
      voice: raw,
      protocol: model.protocolType,
      modelId: modelId,
    );
  }

  String? _trimmedOrNull(String raw) {
    final trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

String _creationQualityLabel(AppLocalizations l10n, String value) {
  return switch (value) {
    'auto' => l10n.creationOptionsQualityAuto,
    'standard' => l10n.creationOptionsQualityStandard,
    'hd' => l10n.creationOptionsQualityHd,
    'high' => l10n.creationOptionsQualityHigh,
    _ => value,
  };
}

String _creationStyleLabel(AppLocalizations l10n, String value) {
  return switch (value) {
    'natural' => l10n.creationOptionsStyleNatural,
    'vivid' => l10n.creationOptionsStyleVivid,
    _ => value,
  };
}

String _creationBackgroundLabel(AppLocalizations l10n, String value) {
  return switch (value) {
    'auto' => l10n.creationOptionsBackgroundAuto,
    'transparent' => l10n.creationOptionsBackgroundTransparent,
    'opaque' => l10n.creationOptionsBackgroundOpaque,
    _ => value,
  };
}

String _creationVideoModeLabel(AppLocalizations l10n, String value) {
  return switch (value) {
    'keyframes' => l10n.creationOptionsModeKeyframes,
    _ => value,
  };
}

String _creationMultiplierLabel(AppLocalizations l10n, num value) {
  final rounded = value.round();
  final text = value == rounded ? '$rounded' : '$value';
  return l10n.creationOptionsMultiplier(text);
}

String _creationModeChipLabel(AppLocalizations l10n, AiCreationMode mode) {
  final label = switch (mode) {
    AiCreationMode.image => l10n.creationOptionsImageMode,
    AiCreationMode.video => l10n.creationOptionsVideoMode,
    AiCreationMode.audio => l10n.creationOptionsAudioMode,
    AiCreationMode.deepResearch => l10n.creationOptionsDeepResearchMode,
    AiCreationMode.none => '',
  };
  return l10n.creationOptionsModeChip(label);
}

List<String> _creationOptionDetailParts(
  AppLocalizations l10n,
  AiCreationOptions options,
) {
  return <String>[
    if (options.aspectRatio != null) options.aspectRatio!,
    if (options.size != null && options.aspectRatio == null) options.size!,
    if (options.durationSeconds != null)
      l10n.creationOptionsDurationSeconds(options.durationSeconds!),
    if (options.resolution != null) options.resolution!,
    if (options.frameRate != null)
      l10n.creationOptionsFrameRateFps(options.frameRate!),
    if (options.numFrames != null)
      l10n.creationOptionsFramesValue(options.numFrames!),
    if (options.quality != null) _creationQualityLabel(l10n, options.quality!),
    if (options.style != null) _creationStyleLabel(l10n, options.style!),
    if (options.outputFormat != null) options.outputFormat!,
    if (options.background != null)
      _creationBackgroundLabel(l10n, options.background!),
    if (options.mode != null) _creationVideoModeLabel(l10n, options.mode!),
    if (options.voice != null) options.voice!,
    if (options.omitVoice) l10n.creationOptionsVoiceUnspecified,
    if (options.speed != null) _creationMultiplierLabel(l10n, options.speed!),
    if (options.sampleRate != null)
      l10n.creationOptionsSampleRateValue(options.sampleRate!),
    if (options.bitrate != null)
      l10n.creationOptionsBitrateKbps(options.bitrate! ~/ 1000),
    if (options.seed != null) l10n.creationOptionsSeedValue('${options.seed}'),
    if (options.promptEnhance != null)
      options.promptEnhance!
          ? l10n.creationOptionsPromptEnhanceOn
          : l10n.creationOptionsPromptEnhanceOff,
    if (options.watermark != null)
      options.watermark!
          ? l10n.creationOptionsWatermarkOn
          : l10n.creationOptionsWatermarkOff,
    if (options.negativePrompt != null) l10n.creationOptionsNegativeOn,
    if (options.count != 1) l10n.creationOptionsCountValue(options.count),
  ];
}

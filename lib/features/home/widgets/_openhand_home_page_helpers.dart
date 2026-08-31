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

const double _kTitleSummaryDialogWidth = 456;
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final total = widget.userMessages.length;
    final selectedCount = _endIdx - _startIdx + 1;
    final sectionStyle = theme.textTheme.labelMedium?.copyWith(
      color: colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
    );
    final selectedCountLabel = openHandLocalizedText(
      context,
      zh: '已选择 $selectedCount 条用户消息',
      zhHant: '已選擇 $selectedCount 則使用者訊息',
      en: 'Selected $selectedCount user messages',
      fr: '$selectedCount messages utilisateur sélectionnés',
      de: '$selectedCount Nutzernachrichten ausgewählt',
      ja: '$selectedCount 件のユーザーメッセージを選択済み',
    );

    String previewLabel(int idx, {int maxLength = 26}) {
      if (idx < 0 || idx >= total) return '#${idx + 1}';
      final content = collapseInlineWhitespace(
        widget.userMessages[idx].content,
      );
      final preview = clipText(content, maxLength - 1);
      return preview.isEmpty ? '#${idx + 1}' : preview;
    }

    return buildOpenHandAlertDialog(
      title: Text(
        _openhandHomePaGenerateAiTitleLabel(context),
        style: theme.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
      content: buildOpenHandDialogConstrainedContent(
        width: _kTitleSummaryDialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(openHandModelLabel(context), style: sectionStyle),
            kOpenHandGap8,
            OpenHandModelSelectorField(
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
            kOpenHandGap18,
            Divider(height: 1, color: colorScheme.outlineVariant),
            kOpenHandGap16,
            Text(
              openHandLocalizedText(
                context,
                zh: '消息范围',
                zhHant: '訊息範圍',
                en: 'Message Range',
                fr: 'Plage de messages',
                de: 'Nachrichtenbereich',
                ja: 'メッセージ範囲',
              ),
              style: sectionStyle,
            ),
            kOpenHandGap10,
            Row(
              children: [
                Expanded(
                  child: _TitleSummaryRangeEndpoint(
                    label: openHandLocalizedText(
                      context,
                      zh: '起始',
                      zhHant: '起始',
                      en: 'From',
                      fr: 'Début',
                      de: 'Von',
                      ja: '開始',
                    ),
                    index: _startIdx,
                    preview: previewLabel(_startIdx),
                  ),
                ),
                kOpenHandHGap12,
                Expanded(
                  child: _TitleSummaryRangeEndpoint(
                    label: openHandLocalizedText(
                      context,
                      zh: '结束',
                      zhHant: '結束',
                      en: 'To',
                      fr: 'Fin',
                      de: 'Bis',
                      ja: '終了',
                    ),
                    index: _endIdx,
                    preview: previewLabel(_endIdx),
                  ),
                ),
              ],
            ),
            kOpenHandGap12,
            Row(
              children: [
                Icon(
                  Icons.format_list_bulleted_rounded,
                  size: 16,
                  color: colorScheme.onSurfaceVariant,
                ),
                kOpenHandHGap6,
                Expanded(
                  child: Text(
                    selectedCountLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            if (total > 1)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: RangeSlider(
                  values: RangeValues(_startIdx.toDouble(), _endIdx.toDouble()),
                  max: (total - 1).toDouble(),
                  divisions: total > 1 ? total - 1 : 1,
                  labels: RangeLabels('#${_startIdx + 1}', '#${_endIdx + 1}'),
                  onChanged: (values) {
                    setState(() {
                      _startIdx = values.start.round();
                      _endIdx = values.end.round();
                    });
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        OpenHandDialogActionButton.secondary(
          onPressed: () => Navigator.of(context).pop(),
          label: AppLocalizations.of(context)!.commonCancel,
        ),
        OpenHandDialogActionButton.primary(
          onPressed: () => Navigator.of(context).pop(
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

class _TitleSummaryRangeEndpoint extends StatelessWidget {
  const _TitleSummaryRangeEndpoint({
    required this.label,
    required this.index,
    required this.preview,
  });

  final String label;
  final int index;
  final String preview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '#${index + 1}',
            style: theme.textTheme.labelLarge?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
          kOpenHandGap3,
          Text(
            preview,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
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
          _openhandHomePaGenerateAiTitleLabel(context),
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
class _CreationOptionsSheet extends StatefulWidget {
  const _CreationOptionsSheet({
    required this.mode,
    required this.initial,
    this.selectedModel,
  });

  final _CreationMode mode;
  final AiCreationOptions initial;
  final AiModelConfig? selectedModel;

  @override
  State<_CreationOptionsSheet> createState() => _CreationOptionsSheetState();
}

class _CreationOptionsSheetState extends State<_CreationOptionsSheet> {
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isImage = widget.mode == _CreationMode.image;
    final isVideo = widget.mode == _CreationMode.video;
    final isAudio = widget.mode == _CreationMode.audio;
    final title = switch (widget.mode) {
      _CreationMode.image => openHandLocalizedText(
        context,
        zh: '图像生成选项',
        en: 'Image options',
      ),
      _CreationMode.video => openHandLocalizedText(
        context,
        zh: '视频生成选项',
        en: 'Video options',
      ),
      _CreationMode.audio => openHandLocalizedText(
        context,
        zh: '音频生成选项',
        en: 'Audio options',
      ),
      _ => openHandLocalizedText(context, zh: '生成选项', en: 'Options'),
    };
    final sectionStyle = theme.textTheme.labelMedium?.copyWith(
      color: cs.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );
    final maxHeight = math.min(MediaQuery.sizeOf(context).height * 0.82, 760.0);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 14,
          bottom: 18 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: cs.outlineVariant.withValues(alpha: 0.55),
                  borderRadius: kOpenHandPillBorderRadius,
                ),
              ),
            ),
            kOpenHandGap16,
            Text(title, style: theme.textTheme.titleMedium),
            kOpenHandGap16,
            Flexible(
              child: SingleChildScrollView(
                physics: openHandDialogAwareScrollPhysics(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (isImage || isVideo) ...[
                      _sectionLabel(
                        context,
                        openHandLocalizedText(
                          context,
                          zh: '宽高比',
                          en: 'Aspect ratio',
                        ),
                        sectionStyle,
                      ),
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
                      kOpenHandGap16,
                    ],
                    if (isVideo || isAudio) ...[
                      _sectionLabel(
                        context,
                        openHandLocalizedText(
                          context,
                          zh: '时长 (秒)',
                          en: 'Duration (s)',
                        ),
                        sectionStyle,
                      ),
                      kOpenHandGap8,
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final d
                              in (isVideo ? _videoDurations : _audioDurations))
                            _optionChip(
                              label: Text('${d}s'),
                              selected: _duration == d,
                              onSelected: () => setState(() => _duration = d),
                            ),
                        ],
                      ),
                      kOpenHandGap16,
                    ],
                    if (isImage) ...[
                      _choiceSection<String>(
                        context: context,
                        title: openHandLocalizedText(
                          context,
                          zh: '质量',
                          en: 'Quality',
                        ),
                        values: _imageQualities,
                        selected: _quality,
                        labelFor: (value) => value,
                        onSelected: (value) => setState(() => _quality = value),
                        sectionStyle: sectionStyle,
                      ),
                      _choiceSection<String>(
                        context: context,
                        title: openHandLocalizedText(
                          context,
                          zh: '风格',
                          en: 'Style',
                        ),
                        values: _imageStyles,
                        selected: _style,
                        labelFor: (value) => value,
                        onSelected: (value) => setState(() => _style = value),
                        sectionStyle: sectionStyle,
                      ),
                      _choiceSection<String>(
                        context: context,
                        title: openHandLocalizedText(
                          context,
                          zh: '输出格式',
                          en: 'Output format',
                        ),
                        values: _imageFormats,
                        selected: _outputFormat,
                        labelFor: (value) => value,
                        onSelected: (value) =>
                            setState(() => _outputFormat = value),
                        sectionStyle: sectionStyle,
                      ),
                      _choiceSection<String>(
                        context: context,
                        title: openHandLocalizedText(
                          context,
                          zh: '背景',
                          en: 'Background',
                        ),
                        values: _imageBackgrounds,
                        selected: _background,
                        labelFor: (value) => value,
                        onSelected: (value) =>
                            setState(() => _background = value),
                        sectionStyle: sectionStyle,
                      ),
                    ],
                    if (isVideo) ...[
                      _choiceSection<String>(
                        context: context,
                        title: openHandLocalizedText(
                          context,
                          zh: '分辨率',
                          en: 'Resolution',
                        ),
                        values: _videoResolutions,
                        selected: _resolution,
                        labelFor: (value) => value,
                        onSelected: (value) =>
                            setState(() => _resolution = value),
                        sectionStyle: sectionStyle,
                      ),
                      _choiceSection<int>(
                        context: context,
                        title: openHandLocalizedText(
                          context,
                          zh: '帧率',
                          en: 'Frame rate',
                        ),
                        values: _videoFrameRates,
                        selected: _frameRate,
                        labelFor: (value) => '$value fps',
                        onSelected: (value) =>
                            setState(() => _frameRate = value),
                        sectionStyle: sectionStyle,
                      ),
                      _choiceSection<int>(
                        context: context,
                        title: openHandLocalizedText(
                          context,
                          zh: '帧数',
                          en: 'Frames',
                        ),
                        values: _videoFrames,
                        selected: _numFrames,
                        labelFor: (value) => '$value',
                        onSelected: (value) =>
                            setState(() => _numFrames = value),
                        sectionStyle: sectionStyle,
                      ),
                      _choiceSection<String>(
                        context: context,
                        title: openHandModeLabel(context),
                        values: _videoModes,
                        selected: _mode,
                        labelFor: (value) => value,
                        onSelected: (value) => setState(() => _mode = value),
                        sectionStyle: sectionStyle,
                      ),
                    ],
                    if (isImage || isVideo) ...[
                      _triBoolSection(
                        context: context,
                        title: openHandLocalizedText(
                          context,
                          zh: 'Prompt 增强',
                          en: 'Prompt enhance',
                        ),
                        value: _promptEnhance,
                        onChanged: (value) =>
                            setState(() => _promptEnhance = value),
                        sectionStyle: sectionStyle,
                      ),
                      _triBoolSection(
                        context: context,
                        title: openHandLocalizedText(
                          context,
                          zh: '水印',
                          en: 'Watermark',
                        ),
                        value: _watermark,
                        onChanged: (value) =>
                            setState(() => _watermark = value),
                        sectionStyle: sectionStyle,
                      ),
                      _textInput(
                        context,
                        label: openHandLocalizedText(
                          context,
                          zh: '负向提示',
                          en: 'Negative prompt',
                        ),
                        controller: _negativePromptController,
                        maxLines: 2,
                      ),
                      kOpenHandGap12,
                      _textInput(
                        context,
                        label: 'Seed',
                        controller: _seedController,
                        keyboardType: TextInputType.number,
                      ),
                      kOpenHandGap16,
                    ],
                    if (isAudio) ...[
                      _audioVoiceSection(context, sectionStyle),
                      _choiceSection<String>(
                        context: context,
                        title: openHandLocalizedText(
                          context,
                          zh: '音频格式',
                          en: 'Audio format',
                        ),
                        values: _audioFormatValues,
                        selected: _outputFormat,
                        labelFor: _audioFormatLabel,
                        onSelected: (value) =>
                            setState(() => _outputFormat = value),
                        sectionStyle: sectionStyle,
                      ),
                      _choiceSection<double>(
                        context: context,
                        title: openHandSpeedLabel(context),
                        values: _audioSpeeds,
                        selected: _speed,
                        labelFor: (value) => '${value}x',
                        onSelected: (value) => setState(() => _speed = value),
                        sectionStyle: sectionStyle,
                      ),
                      _choiceSection<int>(
                        context: context,
                        title: openHandLocalizedText(
                          context,
                          zh: '采样率',
                          en: 'Sample rate',
                        ),
                        values: _audioSampleRates,
                        selected: _sampleRate,
                        labelFor: (value) => '$value',
                        onSelected: (value) =>
                            setState(() => _sampleRate = value),
                        sectionStyle: sectionStyle,
                      ),
                      _choiceSection<int>(
                        context: context,
                        title: openHandLocalizedText(
                          context,
                          zh: '码率',
                          en: 'Bitrate',
                        ),
                        values: _audioBitrateValues,
                        selected: _bitrate,
                        labelFor: (value) => '${value ~/ 1000} kbps',
                        onSelected: (value) => setState(() => _bitrate = value),
                        sectionStyle: sectionStyle,
                      ),
                      _choiceSection<double>(
                        context: context,
                        title: openHandVolumeLabel(context),
                        values: _audioVolumes,
                        selected: _volume,
                        labelFor: (value) => '${value}x',
                        onSelected: (value) => setState(() => _volume = value),
                        sectionStyle: sectionStyle,
                      ),
                      _choiceSection<double>(
                        context: context,
                        title: openHandLocalizedText(
                          context,
                          zh: '音高',
                          en: 'Pitch',
                        ),
                        values: _audioPitches,
                        selected: _pitch,
                        labelFor: (value) => value.toStringAsFixed(0),
                        onSelected: (value) => setState(() => _pitch = value),
                        sectionStyle: sectionStyle,
                      ),
                    ],
                    _countControl(context, sectionStyle),
                  ],
                ),
              ),
            ),
            kOpenHandGap14,
            _actions(context),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(
    BuildContext context,
    String label,
    TextStyle? sectionStyle,
  ) {
    return Text(label, style: sectionStyle);
  }

  Widget _optionChip({
    required Widget label,
    required bool selected,
    required VoidCallback onSelected,
  }) {
    final height = math.max(
      40.0,
      MediaQuery.textScalerOf(context).scale(20) + 16,
    );
    return SizedBox(
      height: height,
      child: ChoiceChip(
        label: label,
        selected: selected,
        onSelected: (_) => onSelected(),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  Widget _choiceSection<T>({
    required BuildContext context,
    required String title,
    required List<T> values,
    required T? selected,
    required String Function(T value) labelFor,
    required ValueChanged<T?> onSelected,
    required TextStyle? sectionStyle,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionLabel(context, title, sectionStyle),
          kOpenHandGap8,
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _optionChip(
                label: Text(_openhandHomePaAutoLabel(context)),
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
      ),
    );
  }

  Widget _triBoolSection({
    required BuildContext context,
    required String title,
    required bool? value,
    required ValueChanged<bool?> onChanged,
    required TextStyle? sectionStyle,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionLabel(context, title, sectionStyle),
          kOpenHandGap8,
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _optionChip(
                label: Text(_openhandHomePaAutoLabel(context)),
                selected: value == null,
                onSelected: () => onChanged(null),
              ),
              _optionChip(
                label: Text(openHandLocalizedText(context, zh: '开', en: 'On')),
                selected: value == true,
                onSelected: () => onChanged(true),
              ),
              _optionChip(
                label: Text(openHandLocalizedText(context, zh: '关', en: 'Off')),
                selected: value == false,
                onSelected: () => onChanged(false),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _audioVoiceSection(BuildContext context, TextStyle? sectionStyle) {
    final options = _audioVoiceOptions;
    final currentVoice = _voiceController.text.trim();
    final selectedKnown = _voiceInCatalog(currentVoice, options);
    final customSelected =
        !_omitVoice && _customVoiceInputVisible && !selectedKnown;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionLabel(context, openHandVoiceLabel(context), sectionStyle),
          kOpenHandGap8,
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _optionChip(
                label: Text(
                  openHandLocalizedText(context, zh: '不指定', en: 'Unspecified'),
                ),
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
                label: Text(
                  openHandLocalizedText(context, zh: '自定义 ID', en: 'Custom ID'),
                ),
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
                      label: openHandLocalizedText(
                        context,
                        zh: '自定义音色 ID',
                        en: 'Custom voice ID',
                      ),
                      controller: _voiceController,
                    ),
                  )
                : const SizedBox(key: ValueKey<String>('preset-audio-voice')),
          ),
        ],
      ),
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
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(borderRadius: kOpenHandBorderRadius12),
      ),
    );
  }

  Widget _countControl(BuildContext context, TextStyle? sectionStyle) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionLabel(
            context,
            openHandLocalizedText(context, zh: '数量', en: 'Count'),
            sectionStyle,
          ),
          kOpenHandGap8,
          Row(
            children: [
              SizedBox(
                width: 46,
                height: 46,
                child: MicroPressFeedback(
                  enabled: _count > 1,
                  child: IconButton(
                    onPressed: _count > 1
                        ? () => setState(() => _count--)
                        : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                ),
              ),
              kOpenHandHGap12,
              Text(
                '$_count',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              kOpenHandHGap12,
              SizedBox(
                width: 46,
                height: 46,
                child: MicroPressFeedback(
                  enabled: _count < 4,
                  child: IconButton(
                    onPressed: _count < 4
                        ? () => setState(() => _count++)
                        : null,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actions(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 10,
      runSpacing: 10,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 128),
          child: OpenHandDialogActionButton.secondary(
            onPressed: () => Navigator.of(context).pop(),
            label: openHandCancelLabel(context),
          ),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 128),
          child: OpenHandDialogActionButton.primary(
            onPressed: () => Navigator.of(context).pop(_selectedOptions()),
            label: openHandConfirmLabel(context),
          ),
        ),
      ],
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

String _openhandHomePaAutoLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '默认', en: 'Auto');
}

String _openhandHomePaGenerateAiTitleLabel(BuildContext context) {
  return openHandGenerateAiTitleLabel(context);
}

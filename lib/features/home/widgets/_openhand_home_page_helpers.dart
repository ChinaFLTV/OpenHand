part of '../openhand_home_page.dart';

class _ComposerDraftState {
  const _ComposerDraftState({required this.text, required this.attachments});

  final String text;
  final List<_ComposerAttachmentDraft> attachments;
}

class _QueuedMessage {
  const _QueuedMessage({
    required this.text,
    required this.attachments,
    this.systemReminders = const <String>[],
    this.skillMetadata,
  });

  final String text;
  final List<_ComposerAttachmentDraft> attachments;
  final List<String> systemReminders;
  final Map<String, Object?>? skillMetadata;
}

// ignore: unused_element
class _EditorPaneFrame extends StatelessWidget {
  // ignore: unused_element_parameter
  const _EditorPaneFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Hot reload can leave an outgoing AnimatedSwitcher child alive for a
    // frame even after the wrapper was removed from the active tree. Keep this
    // shim so stale elements rebuild safely without altering the current UI.
    return child;
  }
}

extension on AppSection {
  /// Returns the drawer index for this section, or -1 if this section
  /// does not correspond to a NavigationDrawerDestination (e.g. workspace
  /// or hardnessSession which are displayed as thread tiles instead).
  /// Using -1 instead of null ensures NavigationDrawer deselects all
  /// destinations when switching to a thread.
  int get drawerIndex {
    return switch (this) {
      AppSection.workspace => -1,
      AppSection.hardnessSession => -1,
      AppSection.automations => 0,
      AppSection.skills => 1,
      AppSection.memory => 2,
      AppSection.mcp => 3,
      AppSection.hooks => 4,
      AppSection.crons => 5,
      AppSection.instructions => 6,
      AppSection.messageGateway => 7,
      AppSection.pluginService => 8,
      AppSection.settings => 9,
    };
  }
}

AppSection _sectionFromDrawerIndex(int index) {
  return switch (index) {
    0 => AppSection.automations,
    1 => AppSection.skills,
    2 => AppSection.memory,
    3 => AppSection.mcp,
    4 => AppSection.hooks,
    5 => AppSection.crons,
    6 => AppSection.instructions,
    7 => AppSection.messageGateway,
    8 => AppSection.pluginService,
    9 => AppSection.settings,
    _ => AppSection.workspace,
  };
}

/// 标题摘要消息区间选择弹窗。返回 (startIndex, endIndex) 或 null。
class _TitleSummaryRangeDialog extends StatefulWidget {
  const _TitleSummaryRangeDialog({required this.userMessages});

  final List<AiSessionMessage> userMessages;

  @override
  State<_TitleSummaryRangeDialog> createState() =>
      _TitleSummaryRangeDialogState();
}

class _TitleSummaryRangeDialogState extends State<_TitleSummaryRangeDialog> {
  late int _startIdx = 0;
  late int _endIdx = (widget.userMessages.length - 1).clamp(0, 2);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final total = widget.userMessages.length;
    final selectedCount = _endIdx - _startIdx + 1;
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');
    // 截取消息内容作为 tooltip 预览
    String previewLabel(int idx) {
      if (idx < 0 || idx >= total) return '#${idx + 1}';
      final content = widget.userMessages[idx].content
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final preview = content.length > 20
          ? '${content.substring(0, 18)}…'
          : content;
      return preview.isEmpty ? '#${idx + 1}' : preview;
    }

    return AlertDialog(
      title: Text(isZh ? '获取 AI 摘要标题' : 'Generate AI Title'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isZh
                  ? '选择参与标题总结的用户消息区间'
                  : 'Select user message range for title summary',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${isZh ? '起始' : 'From'}: #${_startIdx + 1}',
                  style: theme.textTheme.labelMedium,
                ),
                Text(
                  '${isZh ? '结束' : 'To'}: #${_endIdx + 1}',
                  style: theme.textTheme.labelMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (total > 1)
              RangeSlider(
                values: RangeValues(_startIdx.toDouble(), _endIdx.toDouble()),
                max: (total - 1).toDouble(),
                divisions: total > 1 ? total - 1 : 1,
                labels: RangeLabels(
                  previewLabel(_startIdx),
                  previewLabel(_endIdx),
                ),
                onChanged: (values) {
                  setState(() {
                    _startIdx = values.start.round();
                    _endIdx = values.end.round();
                  });
                },
              ),
            const SizedBox(height: 8),
            Text(
              '${isZh ? '已选择' : 'Selected'} $selectedCount ${isZh ? '条用户消息' : 'user messages'}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
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
          onPressed: () => Navigator.of(context).pop((_startIdx, _endIdx)),
          label: isZh ? '生成标题' : 'Generate',
        ),
      ],
    );
  }
}

/// Modal bottom sheet that lets users tweak [AiCreationOptions] for the
/// currently active creation mode. Returns the updated options or null if the
/// user dismissed without confirming.
class _CreationOptionsSheet extends StatefulWidget {
  const _CreationOptionsSheet({required this.mode, required this.initial});

  final _CreationMode mode;
  final AiCreationOptions initial;

  @override
  State<_CreationOptionsSheet> createState() => _CreationOptionsSheetState();
}

class _CreationOptionsSheetState extends State<_CreationOptionsSheet> {
  late String? _aspectRatio = widget.initial.aspectRatio;
  late String? _size = widget.initial.size;
  late int? _duration = widget.initial.durationSeconds;
  late int _count = widget.initial.count;

  // Mode-specific aspect ratio presets with matching pixel sizes. The 1024
  // baseline is used for image generation; video keeps the aspect strings
  // only (pixel sizes are provider-dependent).
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isImage = widget.mode == _CreationMode.image;
    final isVideo = widget.mode == _CreationMode.video;
    final isAudio = widget.mode == _CreationMode.audio;
    final title = switch (widget.mode) {
      _CreationMode.image => _localizedText(
        context,
        zh: '图像生成选项',
        en: 'Image options',
      ),
      _CreationMode.video => _localizedText(
        context,
        zh: '视频生成选项',
        en: 'Video options',
      ),
      _CreationMode.audio => _localizedText(
        context,
        zh: '音频生成选项',
        en: 'Audio options',
      ),
      _ => _localizedText(context, zh: '生成选项', en: 'Options'),
    };
    final sectionStyle = theme.textTheme.labelMedium?.copyWith(
      color: cs.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );
    return Padding(
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
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 16),
          if (isImage || isVideo) ...[
            Text(
              _localizedText(context, zh: '宽高比', en: 'Aspect ratio'),
              style: sectionStyle,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (isImage)
                  for (final preset in _imageRatios)
                    ChoiceChip(
                      label: Text(preset.ratio),
                      selected: _aspectRatio == preset.ratio,
                      onSelected: (_) => setState(() {
                        _aspectRatio = preset.ratio;
                        _size = preset.size;
                      }),
                    ),
                if (isVideo)
                  for (final ratio in _videoRatios)
                    ChoiceChip(
                      label: Text(ratio),
                      selected: _aspectRatio == ratio,
                      onSelected: (_) => setState(() => _aspectRatio = ratio),
                    ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          if (isVideo || isAudio) ...[
            Text(
              _localizedText(context, zh: '时长 (秒)', en: 'Duration (s)'),
              style: sectionStyle,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final d in (isVideo ? _videoDurations : _audioDurations))
                  ChoiceChip(
                    label: Text('${d}s'),
                    selected: _duration == d,
                    onSelected: (_) => setState(() => _duration = d),
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          Text(
            _localizedText(context, zh: '数量', en: 'Count'),
            style: sectionStyle,
          ),
          const SizedBox(height: 8),
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
              const SizedBox(width: 12),
              Text(
                '$_count',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 12),
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
              const SizedBox(width: 16),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Row(
                      children: [
                        OpenHandDialogActionButton.secondary(
                          onPressed: () => Navigator.of(context).pop(),
                          label: _localizedText(
                            context,
                            zh: '取消',
                            en: 'Cancel',
                          ),
                        ),
                        const SizedBox(width: 10),
                        OpenHandDialogActionButton.primary(
                          onPressed: () {
                            Navigator.of(context).pop(
                              AiCreationOptions(
                                size: _size,
                                aspectRatio: _aspectRatio,
                                durationSeconds: _duration,
                                count: _count,
                              ),
                            );
                          },
                          label: _localizedText(
                            context,
                            zh: '确认',
                            en: 'Confirm',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

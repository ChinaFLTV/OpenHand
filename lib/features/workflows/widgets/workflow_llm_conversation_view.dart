import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:provider/provider.dart';

import '../../../app/state/settings_controller.dart';
import '../../../app/theme/openhand_status_colors.dart';
import '../../../shared/ui/motion_durations.dart';
import '../../../shared/ui/motion_preference.dart';
import '../../../shared/ui/openhand_clipboard.dart';
import '../../../shared/ui/openhand_inline_empty_state.dart';
import '../../../shared/ui/openhand_reveal_switcher.dart';
import '../../../shared/ui/openhand_safe_markdown_body.dart';
import '../../../shared/ui/openhand_safe_scrollbar.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../../../shared/ui/openhand_typography.dart';
import '../../../shared/util/date_time_format.dart';
import '../../../shared/util/text_clip.dart';
import '../../ai/index.dart';
import '../service/workflow_node_executor.dart';

const double _messageAvatarSize = 28;
const double _messageActionSize = 30;
const double _messageMaxWidthFactor = 0.9;
const double _autoFollowThreshold = 72;

class WorkflowLlmConversationView extends StatefulWidget {
  const WorkflowLlmConversationView({
    super.key,
    required this.conversation,
    required this.testing,
    required this.ttsPlaybackService,
    required this.translationService,
  });

  final WorkflowLlmConversation? conversation;
  final bool testing;
  final AiTtsPlaybackService ttsPlaybackService;
  final AiTranslationService translationService;

  @override
  State<WorkflowLlmConversationView> createState() =>
      _WorkflowLlmConversationViewState();
}

class _WorkflowLlmConversationViewState
    extends State<WorkflowLlmConversationView> {
  late final ScrollController _scrollController = ScrollController(
    debugLabel: 'workflow-llm-conversation',
  );

  @override
  void didUpdateWidget(covariant WorkflowLlmConversationView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous = oldWidget.conversation;
    final current = widget.conversation;
    if (previous?.startedAt == current?.startedAt &&
        previous?.messages.length == current?.messages.length &&
        previous?.status == current?.status) {
      return;
    }
    final shouldFollow =
        !_scrollController.hasClients ||
        _scrollController.position.maxScrollExtent -
                _scrollController.position.pixels <=
            _autoFollowThreshold;
    if (shouldFollow) _scheduleScrollToBottom();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scheduleScrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      final duration = openHandMotionDuration(context, kOpenHandMotion220);
      if (duration == Duration.zero) {
        _scrollController.jumpTo(target);
      } else {
        unawaited(
          _scrollController.animateTo(
            target,
            duration: duration,
            curve: kOpenHandSwitchInCurve,
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final conversation = widget.conversation;
    final settings = context.watch<SettingsController>();
    return Column(
      children: [
        _ConversationSummary(
          conversation: conversation,
          testing: widget.testing,
        ),
        Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
        Expanded(
          child: conversation == null
              ? OpenHandInlineEmptyState(
                  icon: widget.testing
                      ? Icons.hourglass_top_rounded
                      : Icons.forum_outlined,
                  message: widget.testing
                      ? '正在启动本次虚拟会话…'
                      : '暂无会话记录。\n测试或执行当前 LLM 节点后，这里会保留最近一次完整会话。',
                )
              : _buildMessages(context, conversation, settings),
        ),
      ],
    );
  }

  Widget _buildMessages(
    BuildContext context,
    WorkflowLlmConversation conversation,
    SettingsController settings,
  ) {
    final messages = conversation.messages;
    final fallbackModel = _fallbackModel(conversation, settings);
    return OpenHandSafeScrollbar(
      controller: _scrollController,
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        itemCount: messages.length + (conversation.error == null ? 0 : 1),
        separatorBuilder: (_, _) => kOpenHandGap10,
        itemBuilder: (context, index) {
          if (index == messages.length) {
            return _ConversationErrorCard(message: conversation.error!);
          }
          final message = messages[index];
          return _ConversationMessageCard(
            key: ValueKey<String>(
              '${conversation.startedAt.microsecondsSinceEpoch}-${message.id}',
            ),
            message: message,
            availableModels: settings.aiModels,
            fallbackModel: fallbackModel,
            ttsSettings: settings.aiTtsSettings,
            translationSettings: settings.aiTranslationSettings,
            ttsPlaybackService: widget.ttsPlaybackService,
            translationService: widget.translationService,
          );
        },
      ),
    );
  }

  AiModelConfig? _fallbackModel(
    WorkflowLlmConversation conversation,
    SettingsController settings,
  ) {
    for (final model in settings.aiModels) {
      if (model.id == conversation.modelConfigId &&
          model.allModelIds.contains(conversation.modelId)) {
        return model.copyWith(modelId: conversation.modelId);
      }
    }
    return settings.selectedAiModel;
  }
}

class _ConversationSummary extends StatelessWidget {
  const _ConversationSummary({
    required this.conversation,
    required this.testing,
  });

  final WorkflowLlmConversation? conversation;
  final bool testing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final current = conversation;
    final status = current?.status;
    final (statusLabel, statusColor, statusIcon) = switch (status) {
      WorkflowLlmConversationStatus.running => (
        '进行中',
        OpenHandStatusColors.info,
        Icons.autorenew_rounded,
      ),
      WorkflowLlmConversationStatus.succeeded => (
        '已完成',
        OpenHandStatusColors.success,
        Icons.check_circle_outline_rounded,
      ),
      WorkflowLlmConversationStatus.failed => (
        '执行失败',
        colors.error,
        Icons.error_outline_rounded,
      ),
      null => ('等待执行', colors.onSurfaceVariant, Icons.schedule_rounded),
    };
    return Container(
      margin: const EdgeInsets.all(14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: kOpenHandBorderRadius12,
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.14),
                  borderRadius: kOpenHandBorderRadius10,
                ),
                child: Icon(statusIcon, size: 19, color: statusColor),
              ),
              kOpenHandHGap10,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '最近一次会话',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      current == null
                          ? '执行后将展示完整交互过程'
                          : '${current.modelLabel} · ${current.modelId}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: kOpenHandBorderRadius20,
                  border: Border.all(
                    color: statusColor.withValues(alpha: 0.32),
                  ),
                ),
                child: Text(
                  testing && status == null ? '准备中' : statusLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          if (current != null) ...[
            kOpenHandGap10,
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _SummaryCapsule(
                  icon: Icons.schedule_rounded,
                  label: formatListDateTime(current.startedAt),
                ),
                _SummaryCapsule(
                  icon: Icons.replay_rounded,
                  label: '第 ${current.attempts} 次尝试',
                ),
                _SummaryCapsule(
                  icon: Icons.timer_outlined,
                  label: _formatDuration(current.duration),
                ),
              ],
            ),
          ],
          OpenHandVerticalRevealSwitcher(
            child: status == WorkflowLlmConversationStatus.running
                ? const Padding(
                    key: ValueKey<String>('conversation-progress'),
                    padding: EdgeInsets.only(top: 10),
                    child: ClipRRect(
                      borderRadius: kOpenHandBorderRadius20,
                      child: LinearProgressIndicator(minHeight: 3),
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

class _SummaryCapsule extends StatelessWidget {
  const _SummaryCapsule({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.62,
        ),
        borderRadius: kOpenHandBorderRadius20,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: theme.colorScheme.onSurfaceVariant),
          kOpenHandHGap4,
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConversationMessageCard extends StatefulWidget {
  const _ConversationMessageCard({
    super.key,
    required this.message,
    required this.availableModels,
    required this.fallbackModel,
    required this.ttsSettings,
    required this.translationSettings,
    required this.ttsPlaybackService,
    required this.translationService,
  });

  final WorkflowLlmConversationMessage message;
  final List<AiModelConfig> availableModels;
  final AiModelConfig? fallbackModel;
  final AiTtsSettings ttsSettings;
  final AiTranslationSettings translationSettings;
  final AiTtsPlaybackService ttsPlaybackService;
  final AiTranslationService translationService;

  @override
  State<_ConversationMessageCard> createState() =>
      _ConversationMessageCardState();
}

class _ConversationMessageCardState extends State<_ConversationMessageCard> {
  late bool _expanded = switch (widget.message.kind) {
    WorkflowLlmMessageKind.user || WorkflowLlmMessageKind.assistant => true,
    WorkflowLlmMessageKind.reasoning ||
    WorkflowLlmMessageKind.toolCall ||
    WorkflowLlmMessageKind.toolResult => false,
  };
  bool _translationVisible = false;
  bool _translationLoading = false;
  String? _translation;

  @override
  void didUpdateWidget(covariant _ConversationMessageCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.content == widget.message.content) return;
    _translationVisible = false;
    _translationLoading = false;
    _translation = null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final message = widget.message;
    final user = message.kind == WorkflowLlmMessageKind.user;
    final (label, icon, accent) = switch (message.kind) {
      WorkflowLlmMessageKind.user => (
        '用户',
        Icons.person_outline_rounded,
        colors.primary,
      ),
      WorkflowLlmMessageKind.reasoning => (
        '思考过程',
        Icons.psychology_outlined,
        colors.tertiary,
      ),
      WorkflowLlmMessageKind.assistant => (
        '助手',
        Icons.auto_awesome_outlined,
        colors.primary,
      ),
      WorkflowLlmMessageKind.toolCall => (
        message.toolName?.trim().isNotEmpty == true
            ? '调用 ${message.toolName}'
            : '工具调用',
        Icons.build_outlined,
        OpenHandStatusColors.info,
      ),
      WorkflowLlmMessageKind.toolResult => (
        message.isError ? '工具执行失败' : '工具返回',
        message.isError ? Icons.error_outline_rounded : Icons.task_alt_rounded,
        message.isError ? colors.error : OpenHandStatusColors.success,
      ),
    };
    final collapsible =
        message.kind == WorkflowLlmMessageKind.reasoning ||
        message.kind == WorkflowLlmMessageKind.toolCall ||
        message.kind == WorkflowLlmMessageKind.toolResult;
    final background = user
        ? colors.primaryContainer.withValues(alpha: 0.58)
        : colors.surfaceContainer;
    final card = Container(
      decoration: BoxDecoration(
        color: background,
        borderRadius: kOpenHandBorderRadius12,
        border: Border.all(
          color: user
              ? colors.primary.withValues(alpha: 0.28)
              : colors.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: kOpenHandBorderRadius12,
            onTap: collapsible
                ? () => setState(() => _expanded = !_expanded)
                : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
              child: Row(
                children: [
                  Container(
                    width: _messageAvatarSize,
                    height: _messageAvatarSize,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.14),
                      borderRadius: kOpenHandBorderRadius8,
                    ),
                    child: Icon(icon, size: 16, color: accent),
                  ),
                  kOpenHandHGap8,
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    formatHourMinuteSecondLocal(message.createdAt),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  kOpenHandHGap4,
                  _buildActions(context),
                  if (collapsible) ...[
                    kOpenHandHGap2,
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: colors.onSurfaceVariant,
                    ),
                  ],
                ],
              ),
            ),
          ),
          OpenHandVerticalRevealSwitcher(
            child: _expanded
                ? Padding(
                    key: const ValueKey<String>('message-content'),
                    padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
                    child: _buildContent(context),
                  )
                : null,
          ),
          OpenHandVerticalRevealSwitcher(
            child: _translationVisible && _translation != null
                ? Container(
                    key: const ValueKey<String>('message-translation'),
                    margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colors.secondaryContainer.withValues(alpha: 0.48),
                      borderRadius: kOpenHandBorderRadius10,
                      border: Border.all(
                        color: colors.secondary.withValues(alpha: 0.22),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '译文',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.secondary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        kOpenHandGap6,
                        _MarkdownMessageBody(data: _translation!),
                      ],
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: user ? _messageMaxWidthFactor : 1,
        child: card,
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final kind = widget.message.kind;
    if (kind == WorkflowLlmMessageKind.toolCall ||
        kind == WorkflowLlmMessageKind.toolResult) {
      final theme = Theme.of(context);
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.62,
          ),
          borderRadius: kOpenHandBorderRadius8,
        ),
        child: SelectableText(
          widget.message.content,
          style: openHandCodeBodyTextStyle(
            theme,
            color: theme.colorScheme.onSurface,
          ),
        ),
      );
    }
    return _MarkdownMessageBody(data: widget.message.content);
  }

  Widget _buildActions(BuildContext context) {
    final canTransform = switch (widget.message.kind) {
      WorkflowLlmMessageKind.user ||
      WorkflowLlmMessageKind.reasoning ||
      WorkflowLlmMessageKind.assistant => true,
      WorkflowLlmMessageKind.toolCall ||
      WorkflowLlmMessageKind.toolResult => false,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _MessageActionButton(
          tooltip: '复制',
          icon: Icons.content_copy_rounded,
          onPressed: () => unawaited(
            copyOpenHandTextToClipboard(
              context: context,
              text: widget.message.content,
              logTag: 'workflow_llm_conversation',
            ),
          ),
        ),
        if (canTransform && widget.ttsSettings.enabled) ...[
          kOpenHandHGap4,
          ValueListenableBuilder<AiTtsPlaybackSnapshot>(
            valueListenable: widget.ttsPlaybackService.state,
            builder: (context, playback, _) {
              final playing =
                  playback.playing && playback.messageId == widget.message.id;
              return _MessageActionButton(
                tooltip: playing ? '停止朗读' : '朗读',
                icon: playing
                    ? Icons.stop_circle_outlined
                    : Icons.volume_up_outlined,
                selected: playing,
                onPressed: () => unawaited(_toggleSpeech(context)),
              );
            },
          ),
        ],
        if (canTransform && widget.translationSettings.enabled) ...[
          kOpenHandHGap4,
          _MessageActionButton(
            tooltip: _translationVisible ? '收起译文' : '翻译',
            icon: Icons.translate_rounded,
            selected: _translationVisible,
            loading: _translationLoading,
            onPressed: _translationLoading
                ? null
                : () => unawaited(_toggleTranslation(context)),
          ),
        ],
      ],
    );
  }

  Future<void> _toggleSpeech(BuildContext context) async {
    try {
      await widget.ttsPlaybackService.toggleMessage(
        messageId: widget.message.id,
        text: widget.message.content,
        settings: widget.ttsSettings,
        availableModels: widget.availableModels,
        fallbackModel: widget.fallbackModel,
      );
    } catch (error) {
      if (!context.mounted) return;
      showOpenHandErrorSnack(context, '朗读失败：${_errorText(error)}');
    }
  }

  Future<void> _toggleTranslation(BuildContext context) async {
    if (_translationVisible) {
      setState(() => _translationVisible = false);
      return;
    }
    if (_translation != null) {
      setState(() => _translationVisible = true);
      return;
    }
    setState(() => _translationLoading = true);
    try {
      final result = await widget.translationService.translate(
        text: widget.message.content,
        settings: widget.translationSettings,
        availableModels: widget.availableModels,
        fallbackModel: widget.fallbackModel,
      );
      if (!mounted) return;
      setState(() {
        _translation = result.text;
        _translationVisible = true;
      });
    } catch (error) {
      if (!context.mounted) return;
      showOpenHandErrorSnack(context, '翻译失败：${_errorText(error)}');
    } finally {
      if (mounted) setState(() => _translationLoading = false);
    }
  }
}

class _MessageActionButton extends StatelessWidget {
  const _MessageActionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.selected = false,
    this.loading = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool selected;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: SizedBox.square(
        dimension: _messageActionSize,
        child: IconButton(
          onPressed: onPressed,
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(
            backgroundColor: selected
                ? colors.primaryContainer
                : colors.surfaceContainerHighest.withValues(alpha: 0.72),
            foregroundColor: selected
                ? colors.onPrimaryContainer
                : colors.onSurfaceVariant,
            shape: const CircleBorder(),
          ),
          icon: loading
              ? const SizedBox.square(
                  dimension: 13,
                  child: CircularProgressIndicator(strokeWidth: 1.8),
                )
              : Icon(icon, size: 15),
        ),
      ),
    );
  }
}

class _MarkdownMessageBody extends StatelessWidget {
  const _MarkdownMessageBody({required this.data});

  final String data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final base = theme.textTheme.bodySmall?.copyWith(
      color: colors.onSurface,
      height: 1.48,
    );
    return OpenHandSafeMarkdownBody(
      data: data,
      selectable: true,
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        p: base,
        a: base?.copyWith(
          color: colors.primary,
          decoration: TextDecoration.underline,
        ),
        code: base?.copyWith(
          fontFamily: kOpenHandMonospaceFontFamily,
          backgroundColor: colors.surfaceContainerHighest,
        ),
        codeblockPadding: const EdgeInsets.all(9),
        codeblockDecoration: BoxDecoration(
          color: colors.surfaceContainerHighest.withValues(alpha: 0.72),
          borderRadius: kOpenHandBorderRadius8,
          border: Border.all(color: colors.outlineVariant),
        ),
        blockquotePadding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
        blockquoteDecoration: BoxDecoration(
          color: colors.surfaceContainerHighest.withValues(alpha: 0.48),
          border: Border(left: BorderSide(color: colors.primary, width: 3)),
        ),
        h1: theme.textTheme.titleMedium,
        h2: theme.textTheme.titleSmall,
        h3: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _ConversationErrorCard extends StatelessWidget {
  const _ConversationErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: colors.errorContainer.withValues(alpha: 0.55),
        borderRadius: kOpenHandBorderRadius12,
        border: Border.all(color: colors.error.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, size: 18, color: colors.error),
          kOpenHandHGap8,
          Expanded(
            child: SelectableText(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onErrorContainer,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDuration(Duration duration) {
  if (duration.inMilliseconds < 1000) return '${duration.inMilliseconds} 毫秒';
  return '${(duration.inMilliseconds / 1000).toStringAsFixed(1)} 秒';
}

String _errorText(Object error) {
  final text = error.toString().replaceFirst(RegExp(r'^[^:]+:\s*'), '').trim();
  return clipText(text.isEmpty ? '未知错误' : text, 140);
}

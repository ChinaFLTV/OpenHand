import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:provider/provider.dart';

import '../../../app/state/settings_controller.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/util/localized_text.dart';
import '../knowledge_base_controller.dart';
import 'knowledge_dialog_widgets.dart';

Future<void> showKnowledgeImportDialog(BuildContext context) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => const KnowledgeImportDialog(),
  );
}

class KnowledgeImportDialog extends StatefulWidget {
  const KnowledgeImportDialog({super.key});

  @override
  State<KnowledgeImportDialog> createState() => _KnowledgeImportDialogState();
}

class _KnowledgeImportDialogState extends State<KnowledgeImportDialog> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _content = TextEditingController();
  final TextEditingController _tagInput = TextEditingController();
  final List<String> _tags = <String>[];
  bool _preview = false;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    _tagInput.dispose();
    super.dispose();
  }

  void _addTag() {
    final value = _tagInput.text.trim();
    if (value.isEmpty) return;
    final exists = _tags.any(
      (item) => item.toLowerCase() == value.toLowerCase(),
    );
    if (!exists) {
      setState(() => _tags.add(value));
    }
    _tagInput.clear();
  }

  void _removeTag(String value) {
    setState(() => _tags.remove(value));
  }

  void _insertSnippet(String prefix, String suffix, {String placeholder = ''}) {
    final text = _content.text;
    final selection = _content.selection;
    final safeSelection = selection.isValid
        ? selection
        : TextSelection.collapsed(offset: text.length);
    final start = safeSelection.start.clamp(0, text.length).toInt();
    final end = safeSelection.end.clamp(0, text.length).toInt();
    final selected = start == end ? placeholder : text.substring(start, end);
    final next = text.replaceRange(start, end, '$prefix$selected$suffix');
    final cursor = start + prefix.length + selected.length + suffix.length;
    _content.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: cursor),
    );
  }

  void _prefixCurrentLine(String prefix) {
    final text = _content.text;
    final selection = _content.selection;
    final cursor = selection.isValid
        ? selection.baseOffset.clamp(0, text.length).toInt()
        : text.length;
    final lineStart = text.lastIndexOf('\n', math.max(0, cursor - 1)) + 1;
    _content.value = TextEditingValue(
      text: text.replaceRange(lineStart, lineStart, prefix),
      selection: TextSelection.collapsed(offset: cursor + prefix.length),
    );
  }

  Future<void> _save() async {
    final controller = context.read<KnowledgeBaseController>();
    final settings = context.read<SettingsController>();
    final embeddingModel = controller.resolveEmbeddingModel(settings.aiModels);
    final isZh = openHandIsChineseLocale(context);
    if (embeddingModel == null) {
      OpenHandSnackBar.showError(
        context,
        isZh ? '请先配置可用的嵌入模型。' : 'Configure an embedding model first.',
      );
      return;
    }
    if (_content.text.trim().isEmpty) {
      OpenHandSnackBar.showError(
        context,
        isZh ? '笔记内容不能为空。' : 'Note content cannot be empty.',
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final source = await controller.importNote(
        title: _title.text,
        content: _content.text,
        embeddingModel: embeddingModel,
        tags: List<String>.unmodifiable(_tags),
      );
      if (!mounted) return;
      if (source == null) {
        OpenHandSnackBar.showError(
          context,
          controller.error ?? (isZh ? '笔记导入失败。' : 'Note import failed.'),
        );
        return;
      }
      Navigator.of(context).pop();
      OpenHandSnackBar.showSuccess(
        context,
        isZh ? '笔记已导入并建立索引。' : 'Note imported and indexed.',
      );
    } catch (error) {
      if (!mounted) return;
      OpenHandSnackBar.showError(context, '$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isZh = openHandIsChineseLocale(context);
    final dialogHeight = math.min(
      MediaQuery.sizeOf(context).height * 0.82,
      700.0,
    );
    return buildOpenHandAlertDialog(
      title: Text(isZh ? '新建知识库笔记' : 'New Knowledge Note'),
      content: buildOpenHandDialogConstrainedContent(
        width: 760,
        height: dialogHeight,
        child: _KnowledgeNoteEditor(
          title: _title,
          content: _content,
          tagInput: _tagInput,
          tags: _tags,
          preview: _preview,
          isZh: isZh,
          onTogglePreview: (value) => setState(() => _preview = value),
          onAddTag: _addTag,
          onRemoveTag: _removeTag,
          onBold: () =>
              _insertSnippet('**', '**', placeholder: isZh ? '加粗' : 'bold'),
          onItalic: () =>
              _insertSnippet('*', '*', placeholder: isZh ? '斜体' : 'italic'),
          onCode: () => _insertSnippet('`', '`', placeholder: 'code'),
          onLink: () => _insertSnippet(
            '[',
            '](https://)',
            placeholder: isZh ? '链接文本' : 'link text',
          ),
          onHeading: () => _prefixCurrentLine('## '),
          onList: () => _prefixCurrentLine('- '),
          onQuote: () => _prefixCurrentLine('> '),
        ),
      ),
      actions: [
        OpenHandDialogActionButton.secondary(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          label: isZh ? '取消' : 'Cancel',
        ),
        OpenHandDialogActionButton.primary(
          onPressed: _saving ? null : _save,
          icon: Icons.save_rounded,
          busy: _saving,
          label: isZh ? '保存并索引' : 'Save and Index',
        ),
      ],
    );
  }
}

class _KnowledgeNoteEditor extends StatelessWidget {
  const _KnowledgeNoteEditor({
    required this.title,
    required this.content,
    required this.tagInput,
    required this.tags,
    required this.preview,
    required this.isZh,
    required this.onTogglePreview,
    required this.onAddTag,
    required this.onRemoveTag,
    required this.onBold,
    required this.onItalic,
    required this.onCode,
    required this.onLink,
    required this.onHeading,
    required this.onList,
    required this.onQuote,
  });

  final TextEditingController title;
  final TextEditingController content;
  final TextEditingController tagInput;
  final List<String> tags;
  final bool preview;
  final bool isZh;
  final ValueChanged<bool> onTogglePreview;
  final VoidCallback onAddTag;
  final ValueChanged<String> onRemoveTag;
  final VoidCallback onBold;
  final VoidCallback onItalic;
  final VoidCallback onCode;
  final VoidCallback onLink;
  final VoidCallback onHeading;
  final VoidCallback onList;
  final VoidCallback onQuote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.84),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.78,
                  ),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  Icons.note_add_outlined,
                  size: 17,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isZh ? '笔记内容' : 'Note Content',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment<bool>(
                    value: false,
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: Text(isZh ? '编辑' : 'Edit'),
                  ),
                  ButtonSegment<bool>(
                    value: true,
                    icon: const Icon(Icons.visibility_outlined, size: 16),
                    label: Text(isZh ? '预览' : 'Preview'),
                  ),
                ],
                selected: {preview},
                onSelectionChanged: (values) => onTogglePreview(values.first),
                style: ButtonStyle(
                  visualDensity: const VisualDensity(
                    horizontal: -2,
                    vertical: -2,
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: WidgetStatePropertyAll(
                    theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: title,
            decoration: knowledgeDialogInputDecoration(
              context,
              isZh ? '标题' : 'Title',
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: tagInput,
                  onSubmitted: (_) => onAddTag(),
                  decoration: knowledgeDialogInputDecoration(
                    context,
                    isZh ? '标签' : 'Tag',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 48,
                child: FilledButton.tonalIcon(
                  onPressed: onAddTag,
                  icon: const Icon(Icons.add_rounded),
                  label: Text(isZh ? '添加' : 'Add'),
                ),
              ),
            ],
          ),
          if (tags.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in tags)
                  InputChip(
                    label: Text(tag),
                    avatar: const Icon(Icons.sell_outlined, size: 15),
                    onDeleted: () => onRemoveTag(tag),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          _MarkdownToolbar(
            isZh: isZh,
            onBold: onBold,
            onItalic: onItalic,
            onCode: onCode,
            onLink: onLink,
            onHeading: onHeading,
            onList: onList,
            onQuote: onQuote,
          ),
          const SizedBox(height: 10),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: preview
                  ? _MarkdownPreview(
                      key: const ValueKey<String>('preview'),
                      controller: content,
                      isZh: isZh,
                    )
                  : _MarkdownTextEditor(
                      key: const ValueKey<String>('editor'),
                      controller: content,
                      isZh: isZh,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MarkdownToolbar extends StatelessWidget {
  const _MarkdownToolbar({
    required this.isZh,
    required this.onBold,
    required this.onItalic,
    required this.onCode,
    required this.onLink,
    required this.onHeading,
    required this.onList,
    required this.onQuote,
  });

  final bool isZh;
  final VoidCallback onBold;
  final VoidCallback onItalic;
  final VoidCallback onCode;
  final VoidCallback onLink;
  final VoidCallback onHeading;
  final VoidCallback onList;
  final VoidCallback onQuote;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.46),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.72),
        ),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          _ToolbarButton(
            tooltip: isZh ? '标题' : 'Heading',
            icon: Icons.title_rounded,
            onPressed: onHeading,
          ),
          _ToolbarButton(
            tooltip: isZh ? '加粗' : 'Bold',
            icon: Icons.format_bold_rounded,
            onPressed: onBold,
          ),
          _ToolbarButton(
            tooltip: isZh ? '斜体' : 'Italic',
            icon: Icons.format_italic_rounded,
            onPressed: onItalic,
          ),
          _ToolbarButton(
            tooltip: isZh ? '代码' : 'Code',
            icon: Icons.code_rounded,
            onPressed: onCode,
          ),
          _ToolbarButton(
            tooltip: isZh ? '列表' : 'List',
            icon: Icons.format_list_bulleted_rounded,
            onPressed: onList,
          ),
          _ToolbarButton(
            tooltip: isZh ? '引用' : 'Quote',
            icon: Icons.format_quote_rounded,
            onPressed: onQuote,
          ),
          _ToolbarButton(
            tooltip: isZh ? '链接' : 'Link',
            icon: Icons.link_rounded,
            onPressed: onLink,
          ),
        ],
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton.filledTonal(
        onPressed: onPressed,
        icon: Icon(icon),
        iconSize: 18,
        constraints: const BoxConstraints.tightFor(width: 36, height: 36),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _MarkdownTextEditor extends StatelessWidget {
  const _MarkdownTextEditor({
    super.key,
    required this.controller,
    required this.isZh,
  });

  final TextEditingController controller;
  final bool isZh;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      expands: true,
      maxLines: null,
      textAlignVertical: TextAlignVertical.top,
      decoration: knowledgeDialogInputDecoration(
        context,
        isZh ? 'Markdown 内容' : 'Markdown content',
        alignLabelWithHint: true,
      ),
    );
  }
}

class _MarkdownPreview extends StatelessWidget {
  const _MarkdownPreview({
    super.key,
    required this.controller,
    required this.isZh,
  });

  final TextEditingController controller;
  final bool isZh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.46),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.84),
        ),
      ),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          final data = value.text.trim();
          if (data.isEmpty) {
            return Center(
              child: Text(
                isZh ? '暂无内容可预览。' : 'Nothing to preview yet.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            );
          }
          return Markdown(
            data: data,
            selectable: true,
            softLineBreak: true,
            extensionSet: md.ExtensionSet.gitHubFlavored,
            styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
              p: theme.textTheme.bodyMedium?.copyWith(height: 1.42),
              code: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace',
                color: colorScheme.onSurface,
              ),
              codeblockDecoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(10),
              ),
              blockquoteDecoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(10),
                border: Border(
                  left: BorderSide(color: colorScheme.primary, width: 3),
                ),
              ),
            ),
            padding: const EdgeInsets.all(12),
          );
        },
      ),
    );
  }
}

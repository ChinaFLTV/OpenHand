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
import '../model/knowledge_source.dart';
import '../service/knowledge_indexing_control.dart';
import 'knowledge_dialog_widgets.dart';
import 'knowledge_indexing_progress_dialog.dart';

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
  final List<TextEditingValue> _undoStack = <TextEditingValue>[];
  final List<TextEditingValue> _redoStack = <TextEditingValue>[];
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

  void _replaceContent(TextEditingValue value) {
    _undoStack.add(_content.value);
    if (_undoStack.length > 80) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
    _content.value = value;
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(_content.value);
    _content.value = _undoStack.removeLast();
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(_content.value);
    _content.value = _redoStack.removeLast();
  }

  TextSelection _safeSelection(String text) {
    final selection = _content.selection;
    return selection.isValid
        ? selection
        : TextSelection.collapsed(offset: text.length);
  }

  void _insertSnippet(
    String prefix,
    String suffix, {
    String placeholder = '',
    int? cursorOffset,
  }) {
    final text = _content.text;
    final safeSelection = _safeSelection(text);
    final start = safeSelection.start.clamp(0, text.length).toInt();
    final end = safeSelection.end.clamp(0, text.length).toInt();
    final selected = start == end ? placeholder : text.substring(start, end);
    final next = text.replaceRange(start, end, '$prefix$selected$suffix');
    final cursor =
        start +
        (cursorOffset ?? prefix.length + selected.length + suffix.length);
    _replaceContent(
      TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: cursor),
      ),
    );
  }

  void _prefixSelectedLines(String prefix) {
    final text = _content.text;
    final selection = _safeSelection(text);
    final start = selection.start.clamp(0, text.length).toInt();
    final end = selection.end.clamp(0, text.length).toInt();
    final lineStart = text.lastIndexOf('\n', math.max(0, start - 1)) + 1;
    final lineEnd = end >= text.length ? text.length : text.indexOf('\n', end);
    final effectiveEnd = lineEnd < 0 ? text.length : lineEnd;
    final block = text.substring(lineStart, effectiveEnd);
    final lines = block.split('\n');
    final replacement = lines.map((line) => '$prefix$line').join('\n');
    _replaceContent(
      TextEditingValue(
        text: text.replaceRange(lineStart, effectiveEnd, replacement),
        selection: TextSelection(
          baseOffset: start + prefix.length,
          extentOffset: end + prefix.length * lines.length,
        ),
      ),
    );
  }

  void _insertBlock(String block) {
    final text = _content.text;
    final selection = _safeSelection(text);
    final start = selection.start.clamp(0, text.length).toInt();
    final end = selection.end.clamp(0, text.length).toInt();
    final needsLeadingBreak =
        start > 0 && !text.substring(0, start).endsWith('\n');
    final needsTrailingBreak =
        end < text.length && !text.substring(end).startsWith('\n');
    final insert =
        '${needsLeadingBreak ? '\n' : ''}$block${needsTrailingBreak ? '\n' : ''}';
    _replaceContent(
      TextEditingValue(
        text: text.replaceRange(start, end, insert),
        selection: TextSelection.collapsed(offset: start + insert.length),
      ),
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
    final cancelToken = KnowledgeIndexingCancelToken();
    final progressController = KnowledgeIndexingProgressController(
      cancelToken: cancelToken,
      initialProgress: KnowledgeIndexingProgress(
        sourceTitle: _title.text.trim().isEmpty
            ? (isZh ? 'OpenHand 笔记' : 'OpenHand Note')
            : _title.text.trim(),
      ),
    );
    try {
      final source = await runKnowledgeIndexingProgressTask<KnowledgeSource>(
        context: context,
        controller: progressController,
        title: isZh ? '构建知识库向量' : 'Building Knowledge Vectors',
        subtitle: isZh ? '正在保存并索引笔记。' : 'Saving and indexing the note.',
        task: () => controller.importNote(
          title: _title.text,
          content: _content.text,
          embeddingModel: embeddingModel,
          tags: List<String>.unmodifiable(_tags),
          cancelToken: cancelToken,
          onProgress: progressController.updateProgress,
        ),
      );
      if (!mounted) return;
      if (cancelToken.isCancelled) {
        OpenHandSnackBar.showInfo(
          context,
          isZh ? '已停止构建向量。' : 'Vector indexing stopped.',
        );
        return;
      }
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
      if (error is KnowledgeIndexingCancelledException ||
          cancelToken.isCancelled) {
        OpenHandSnackBar.showInfo(
          context,
          isZh ? '已停止构建向量。' : 'Vector indexing stopped.',
        );
        return;
      }
      OpenHandSnackBar.showError(context, '$error');
    } finally {
      progressController.dispose();
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
          onUndo: _undo,
          onRedo: _redo,
          onBold: () =>
              _insertSnippet('**', '**', placeholder: isZh ? '加粗' : 'bold'),
          onItalic: () =>
              _insertSnippet('*', '*', placeholder: isZh ? '斜体' : 'italic'),
          onStrike: () => _insertSnippet(
            '~~',
            '~~',
            placeholder: isZh ? '删除线' : 'strikethrough',
          ),
          onCode: () => _insertSnippet('`', '`', placeholder: 'code'),
          onCodeBlock: () => _insertBlock(
            '```dart\n${isZh ? '// 在这里输入代码' : '// code here'}\n```',
          ),
          onLink: () => _insertSnippet(
            '[',
            '](https://)',
            placeholder: isZh ? '链接文本' : 'link text',
            cursorOffset: (isZh ? '链接文本' : 'link text').length + 3,
          ),
          onImage: () => _insertSnippet(
            '![',
            '](https://)',
            placeholder: isZh ? '图片描述' : 'image alt',
            cursorOffset: (isZh ? '图片描述' : 'image alt').length + 4,
          ),
          onHeading1: () => _prefixSelectedLines('# '),
          onHeading2: () => _prefixSelectedLines('## '),
          onHeading3: () => _prefixSelectedLines('### '),
          onBulletList: () => _prefixSelectedLines('- '),
          onOrderedList: () => _prefixSelectedLines('1. '),
          onTaskList: () => _prefixSelectedLines('- [ ] '),
          onQuote: () => _prefixSelectedLines('> '),
          onDivider: () => _insertBlock('---'),
          onTable: () => _insertBlock(
            '| ${isZh ? '字段' : 'Field'} | ${isZh ? '说明' : 'Description'} |\n'
            '| --- | --- |\n'
            '|  |  |',
          ),
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
    required this.onUndo,
    required this.onRedo,
    required this.onBold,
    required this.onItalic,
    required this.onStrike,
    required this.onCode,
    required this.onCodeBlock,
    required this.onLink,
    required this.onImage,
    required this.onHeading1,
    required this.onHeading2,
    required this.onHeading3,
    required this.onBulletList,
    required this.onOrderedList,
    required this.onTaskList,
    required this.onQuote,
    required this.onDivider,
    required this.onTable,
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
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onBold;
  final VoidCallback onItalic;
  final VoidCallback onStrike;
  final VoidCallback onCode;
  final VoidCallback onCodeBlock;
  final VoidCallback onLink;
  final VoidCallback onImage;
  final VoidCallback onHeading1;
  final VoidCallback onHeading2;
  final VoidCallback onHeading3;
  final VoidCallback onBulletList;
  final VoidCallback onOrderedList;
  final VoidCallback onTaskList;
  final VoidCallback onQuote;
  final VoidCallback onDivider;
  final VoidCallback onTable;

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
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 116),
                child: SizedBox(
                  height: 48,
                  child: FilledButton.tonalIcon(
                    onPressed: onAddTag,
                    icon: const Icon(Icons.add_rounded),
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        isZh ? '添加' : 'Add',
                        maxLines: 1,
                        softWrap: false,
                      ),
                    ),
                  ),
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
            onUndo: onUndo,
            onRedo: onRedo,
            onBold: onBold,
            onItalic: onItalic,
            onStrike: onStrike,
            onCode: onCode,
            onCodeBlock: onCodeBlock,
            onLink: onLink,
            onImage: onImage,
            onHeading1: onHeading1,
            onHeading2: onHeading2,
            onHeading3: onHeading3,
            onBulletList: onBulletList,
            onOrderedList: onOrderedList,
            onTaskList: onTaskList,
            onQuote: onQuote,
            onDivider: onDivider,
            onTable: onTable,
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
    required this.onUndo,
    required this.onRedo,
    required this.onBold,
    required this.onItalic,
    required this.onStrike,
    required this.onCode,
    required this.onCodeBlock,
    required this.onLink,
    required this.onImage,
    required this.onHeading1,
    required this.onHeading2,
    required this.onHeading3,
    required this.onBulletList,
    required this.onOrderedList,
    required this.onTaskList,
    required this.onQuote,
    required this.onDivider,
    required this.onTable,
  });

  final bool isZh;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onBold;
  final VoidCallback onItalic;
  final VoidCallback onStrike;
  final VoidCallback onCode;
  final VoidCallback onCodeBlock;
  final VoidCallback onLink;
  final VoidCallback onImage;
  final VoidCallback onHeading1;
  final VoidCallback onHeading2;
  final VoidCallback onHeading3;
  final VoidCallback onBulletList;
  final VoidCallback onOrderedList;
  final VoidCallback onTaskList;
  final VoidCallback onQuote;
  final VoidCallback onDivider;
  final VoidCallback onTable;

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
            tooltip: isZh ? '撤销' : 'Undo',
            icon: Icons.undo_rounded,
            onPressed: onUndo,
          ),
          _ToolbarButton(
            tooltip: isZh ? '重做' : 'Redo',
            icon: Icons.redo_rounded,
            onPressed: onRedo,
          ),
          _ToolbarDivider(),
          _ToolbarButton(
            tooltip: isZh ? '一级标题' : 'Heading 1',
            label: 'H1',
            onPressed: onHeading1,
          ),
          _ToolbarButton(
            tooltip: isZh ? '二级标题' : 'Heading 2',
            label: 'H2',
            onPressed: onHeading2,
          ),
          _ToolbarButton(
            tooltip: isZh ? '三级标题' : 'Heading 3',
            label: 'H3',
            onPressed: onHeading3,
          ),
          _ToolbarDivider(),
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
            tooltip: isZh ? '删除线' : 'Strikethrough',
            icon: Icons.format_strikethrough_rounded,
            onPressed: onStrike,
          ),
          _ToolbarButton(
            tooltip: isZh ? '代码' : 'Code',
            icon: Icons.code_rounded,
            onPressed: onCode,
          ),
          _ToolbarButton(
            tooltip: isZh ? '代码块' : 'Code block',
            icon: Icons.integration_instructions_rounded,
            onPressed: onCodeBlock,
          ),
          _ToolbarDivider(),
          _ToolbarButton(
            tooltip: isZh ? '无序列表' : 'Bullet list',
            icon: Icons.format_list_bulleted_rounded,
            onPressed: onBulletList,
          ),
          _ToolbarButton(
            tooltip: isZh ? '有序列表' : 'Ordered list',
            icon: Icons.format_list_numbered_rounded,
            onPressed: onOrderedList,
          ),
          _ToolbarButton(
            tooltip: isZh ? '任务列表' : 'Task list',
            icon: Icons.checklist_rounded,
            onPressed: onTaskList,
          ),
          _ToolbarButton(
            tooltip: isZh ? '引用' : 'Quote',
            icon: Icons.format_quote_rounded,
            onPressed: onQuote,
          ),
          _ToolbarDivider(),
          _ToolbarButton(
            tooltip: isZh ? '链接' : 'Link',
            icon: Icons.link_rounded,
            onPressed: onLink,
          ),
          _ToolbarButton(
            tooltip: isZh ? '图片' : 'Image',
            icon: Icons.image_outlined,
            onPressed: onImage,
          ),
          _ToolbarButton(
            tooltip: isZh ? '表格' : 'Table',
            icon: Icons.table_chart_outlined,
            onPressed: onTable,
          ),
          _ToolbarButton(
            tooltip: isZh ? '分割线' : 'Divider',
            icon: Icons.horizontal_rule_rounded,
            onPressed: onDivider,
          ),
        ],
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.tooltip,
    required this.onPressed,
    this.icon,
    this.label,
  });

  final String tooltip;
  final IconData? icon;
  final String? label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton.filledTonal(
        onPressed: onPressed,
        icon: icon == null
            ? Text(
                label ?? '',
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w900),
              )
            : Icon(icon),
        iconSize: 18,
        constraints: const BoxConstraints.tightFor(width: 36, height: 36),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _ToolbarDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 8,
      height: 36,
      child: Center(
        child: Container(
          width: 1,
          height: 20,
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
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

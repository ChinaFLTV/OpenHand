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

String _kbImportText(
  BuildContext context, {
  required String zh,
  required String en,
  String? zhHans,
  String? zhHant,
  String? fr,
  String? de,
  String? ja,
}) {
  return openHandLocalizedText(
    context,
    zh: zh,
    en: en,
    zhHans: zhHans,
    zhHant: zhHant,
    fr: fr,
    de: de,
    ja: ja,
  );
}

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
    if (embeddingModel == null) {
      OpenHandSnackBar.showError(
        context,
        _kbImportText(
          context,
          zh: '请先配置可用的嵌入模型。',
          zhHant: '請先設定可用的嵌入模型。',
          en: 'Configure an embedding model first.',
          fr: 'Configurez d’abord un modèle d’embedding.',
          de: 'Konfigurieren Sie zuerst ein Embedding-Modell.',
          ja: '先に利用可能な埋め込みモデルを設定してください。',
        ),
      );
      return;
    }
    if (_content.text.trim().isEmpty) {
      OpenHandSnackBar.showError(
        context,
        _kbImportText(
          context,
          zh: '笔记内容不能为空。',
          zhHant: '筆記內容不能為空。',
          en: 'Note content cannot be empty.',
          fr: 'Le contenu de la note ne peut pas être vide.',
          de: 'Der Notizinhalt darf nicht leer sein.',
          ja: 'ノートの内容は空にできません。',
        ),
      );
      return;
    }
    setState(() => _saving = true);
    final cancelToken = KnowledgeIndexingCancelToken();
    final progressController = KnowledgeIndexingProgressController(
      cancelToken: cancelToken,
      initialProgress: KnowledgeIndexingProgress(
        sourceTitle: _title.text.trim().isEmpty
            ? _kbImportText(
                context,
                zh: 'OpenHand 笔记',
                zhHant: 'OpenHand 筆記',
                en: 'OpenHand Note',
                fr: 'Note OpenHand',
                de: 'OpenHand-Notiz',
                ja: 'OpenHand ノート',
              )
            : _title.text.trim(),
      ),
    );
    try {
      final source = await runKnowledgeIndexingProgressTask<KnowledgeSource>(
        context: context,
        controller: progressController,
        title: _kbImportText(
          context,
          zh: '构建知识库向量',
          zhHant: '建立知識庫向量',
          en: 'Building Knowledge Vectors',
          fr: 'Construction des vecteurs',
          de: 'Wissensvektoren werden erstellt',
          ja: 'ナレッジベースベクトルを構築',
        ),
        subtitle: _kbImportText(
          context,
          zh: '正在保存并索引笔记。',
          zhHant: '正在儲存並索引筆記。',
          en: 'Saving and indexing the note.',
          fr: 'Enregistrement et indexation de la note.',
          de: 'Notiz wird gespeichert und indexiert.',
          ja: 'ノートを保存してインデックス化しています。',
        ),
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
          _kbImportText(
            context,
            zh: '已停止构建向量。',
            zhHant: '已停止建立向量。',
            en: 'Vector indexing stopped.',
            fr: 'Indexation vectorielle arrêtée.',
            de: 'Vektorindexierung gestoppt.',
            ja: 'ベクトルのインデックス作成を停止しました。',
          ),
        );
        return;
      }
      if (source == null) {
        OpenHandSnackBar.showError(
          context,
          controller.error ??
              _kbImportText(
                context,
                zh: '笔记导入失败。',
                zhHant: '筆記匯入失敗。',
                en: 'Note import failed.',
                fr: 'Échec de l’import de la note.',
                de: 'Notizimport fehlgeschlagen.',
                ja: 'ノートのインポートに失敗しました。',
              ),
        );
        return;
      }
      Navigator.of(context).pop();
      OpenHandSnackBar.showSuccess(
        context,
        _kbImportText(
          context,
          zh: '笔记已导入并建立索引。',
          zhHant: '筆記已匯入並建立索引。',
          en: 'Note imported and indexed.',
          fr: 'Note importée et indexée.',
          de: 'Notiz importiert und indexiert.',
          ja: 'ノートをインポートしてインデックス化しました。',
        ),
      );
    } catch (error) {
      if (!mounted) return;
      if (error is KnowledgeIndexingCancelledException ||
          cancelToken.isCancelled) {
        OpenHandSnackBar.showInfo(
          context,
          _kbImportText(
            context,
            zh: '已停止构建向量。',
            zhHant: '已停止建立向量。',
            en: 'Vector indexing stopped.',
            fr: 'Indexation vectorielle arrêtée.',
            de: 'Vektorindexierung gestoppt.',
            ja: 'ベクトルのインデックス作成を停止しました。',
          ),
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
    String t({
      required String zh,
      required String en,
      String? zhHans,
      String? zhHant,
      String? fr,
      String? de,
      String? ja,
    }) {
      return _kbImportText(
        context,
        zh: zh,
        en: en,
        zhHans: zhHans,
        zhHant: zhHant,
        fr: fr,
        de: de,
        ja: ja,
      );
    }

    final boldPlaceholder = t(
      zh: '加粗',
      zhHant: '粗體',
      en: 'bold',
      fr: 'gras',
      de: 'fett',
      ja: '太字',
    );
    final italicPlaceholder = t(
      zh: '斜体',
      zhHant: '斜體',
      en: 'italic',
      fr: 'italique',
      de: 'kursiv',
      ja: '斜体',
    );
    final strikePlaceholder = t(
      zh: '删除线',
      zhHant: '刪除線',
      en: 'strikethrough',
      fr: 'barré',
      de: 'durchgestrichen',
      ja: '取り消し線',
    );
    final codeComment = t(
      zh: '// 在这里输入代码',
      zhHant: '// 在這裡輸入程式碼',
      en: '// code here',
      fr: '// code ici',
      de: '// Code hier',
      ja: '// ここにコード',
    );
    final linkText = t(
      zh: '链接文本',
      zhHant: '連結文字',
      en: 'link text',
      fr: 'texte du lien',
      de: 'Linktext',
      ja: 'リンクテキスト',
    );
    final imageAlt = t(
      zh: '图片描述',
      zhHant: '圖片描述',
      en: 'image alt',
      fr: 'description image',
      de: 'Bildbeschreibung',
      ja: '画像の説明',
    );
    final dialogHeight = math.min(
      MediaQuery.sizeOf(context).height * 0.82,
      700.0,
    );
    return buildOpenHandAlertDialog(
      title: Text(
        t(
          zh: '新建知识库笔记',
          zhHant: '新增知識庫筆記',
          en: 'New Knowledge Note',
          fr: 'Nouvelle note de connaissance',
          de: 'Neue Wissensnotiz',
          ja: '新規ナレッジノート',
        ),
      ),
      content: buildOpenHandDialogConstrainedContent(
        width: 760,
        height: dialogHeight,
        child: _KnowledgeNoteEditor(
          title: _title,
          content: _content,
          tagInput: _tagInput,
          tags: _tags,
          preview: _preview,
          onTogglePreview: (value) => setState(() => _preview = value),
          onAddTag: _addTag,
          onRemoveTag: _removeTag,
          onUndo: _undo,
          onRedo: _redo,
          onBold: () =>
              _insertSnippet('**', '**', placeholder: boldPlaceholder),
          onItalic: () =>
              _insertSnippet('*', '*', placeholder: italicPlaceholder),
          onStrike: () =>
              _insertSnippet('~~', '~~', placeholder: strikePlaceholder),
          onCode: () => _insertSnippet('`', '`', placeholder: 'code'),
          onCodeBlock: () => _insertBlock('```dart\n$codeComment\n```'),
          onLink: () => _insertSnippet(
            '[',
            '](https://)',
            placeholder: linkText,
            cursorOffset: linkText.length + 3,
          ),
          onImage: () => _insertSnippet(
            '![',
            '](https://)',
            placeholder: imageAlt,
            cursorOffset: imageAlt.length + 4,
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
            '| ${t(zh: '字段', zhHant: '欄位', en: 'Field', fr: 'Champ', de: 'Feld', ja: '項目')} | ${t(zh: '说明', zhHant: '說明', en: 'Description', fr: 'Description', de: 'Beschreibung', ja: '説明')} |\n'
            '| --- | --- |\n'
            '|  |  |',
          ),
        ),
      ),
      actions: [
        OpenHandDialogActionButton.secondary(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          label: t(
            zh: '取消',
            zhHant: '取消',
            en: 'Cancel',
            fr: 'Annuler',
            de: 'Abbrechen',
            ja: 'キャンセル',
          ),
        ),
        OpenHandDialogActionButton.primary(
          onPressed: _saving ? null : _save,
          icon: Icons.save_rounded,
          busy: _saving,
          label: t(
            zh: '保存并索引',
            zhHant: '儲存並索引',
            en: 'Save and Index',
            fr: 'Enregistrer et indexer',
            de: 'Speichern und indexieren',
            ja: '保存してインデックス',
          ),
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
                  _kbImportText(
                    context,
                    zh: '笔记内容',
                    zhHant: '筆記內容',
                    en: 'Note Content',
                    fr: 'Contenu de la note',
                    de: 'Notizinhalt',
                    ja: 'ノート内容',
                  ),
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
                    label: Text(
                      _kbImportText(
                        context,
                        zh: '编辑',
                        zhHant: '編輯',
                        en: 'Edit',
                        fr: 'Éditer',
                        de: 'Bearbeiten',
                        ja: '編集',
                      ),
                    ),
                  ),
                  ButtonSegment<bool>(
                    value: true,
                    icon: const Icon(Icons.visibility_outlined, size: 16),
                    label: Text(
                      _kbImportText(
                        context,
                        zh: '预览',
                        zhHant: '預覽',
                        en: 'Preview',
                        fr: 'Aperçu',
                        de: 'Vorschau',
                        ja: 'プレビュー',
                      ),
                    ),
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
              _kbImportText(
                context,
                zh: '标题',
                zhHant: '標題',
                en: 'Title',
                fr: 'Titre',
                de: 'Titel',
                ja: 'タイトル',
              ),
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
                    _kbImportText(
                      context,
                      zh: '标签',
                      zhHant: '標籤',
                      en: 'Tag',
                      fr: 'Étiquette',
                      de: 'Tag',
                      ja: 'タグ',
                    ),
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
                        _kbImportText(
                          context,
                          zh: '添加',
                          zhHant: '新增',
                          en: 'Add',
                          fr: 'Ajouter',
                          de: 'Hinzufügen',
                          ja: '追加',
                        ),
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
                    )
                  : _MarkdownTextEditor(
                      key: const ValueKey<String>('editor'),
                      controller: content,
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
            tooltip: _kbImportText(
              context,
              zh: '撤销',
              zhHant: '復原',
              en: 'Undo',
              fr: 'Annuler',
              de: 'Rückgängig',
              ja: '元に戻す',
            ),
            icon: Icons.undo_rounded,
            onPressed: onUndo,
          ),
          _ToolbarButton(
            tooltip: _kbImportText(
              context,
              zh: '重做',
              zhHant: '重做',
              en: 'Redo',
              fr: 'Rétablir',
              de: 'Wiederholen',
              ja: 'やり直す',
            ),
            icon: Icons.redo_rounded,
            onPressed: onRedo,
          ),
          _ToolbarDivider(),
          _ToolbarButton(
            tooltip: _kbImportText(
              context,
              zh: '一级标题',
              zhHant: '一級標題',
              en: 'Heading 1',
              fr: 'Titre 1',
              de: 'Überschrift 1',
              ja: '見出し 1',
            ),
            label: 'H1',
            onPressed: onHeading1,
          ),
          _ToolbarButton(
            tooltip: _kbImportText(
              context,
              zh: '二级标题',
              zhHant: '二級標題',
              en: 'Heading 2',
              fr: 'Titre 2',
              de: 'Überschrift 2',
              ja: '見出し 2',
            ),
            label: 'H2',
            onPressed: onHeading2,
          ),
          _ToolbarButton(
            tooltip: _kbImportText(
              context,
              zh: '三级标题',
              zhHant: '三級標題',
              en: 'Heading 3',
              fr: 'Titre 3',
              de: 'Überschrift 3',
              ja: '見出し 3',
            ),
            label: 'H3',
            onPressed: onHeading3,
          ),
          _ToolbarDivider(),
          _ToolbarButton(
            tooltip: _kbImportText(
              context,
              zh: '加粗',
              zhHant: '粗體',
              en: 'Bold',
              fr: 'Gras',
              de: 'Fett',
              ja: '太字',
            ),
            icon: Icons.format_bold_rounded,
            onPressed: onBold,
          ),
          _ToolbarButton(
            tooltip: _kbImportText(
              context,
              zh: '斜体',
              zhHant: '斜體',
              en: 'Italic',
              fr: 'Italique',
              de: 'Kursiv',
              ja: '斜体',
            ),
            icon: Icons.format_italic_rounded,
            onPressed: onItalic,
          ),
          _ToolbarButton(
            tooltip: _kbImportText(
              context,
              zh: '删除线',
              zhHant: '刪除線',
              en: 'Strikethrough',
              fr: 'Barré',
              de: 'Durchgestrichen',
              ja: '取り消し線',
            ),
            icon: Icons.format_strikethrough_rounded,
            onPressed: onStrike,
          ),
          _ToolbarButton(
            tooltip: _kbImportText(
              context,
              zh: '代码',
              zhHant: '程式碼',
              en: 'Code',
              fr: 'Code',
              de: 'Code',
              ja: 'コード',
            ),
            icon: Icons.code_rounded,
            onPressed: onCode,
          ),
          _ToolbarButton(
            tooltip: _kbImportText(
              context,
              zh: '代码块',
              zhHant: '程式碼區塊',
              en: 'Code block',
              fr: 'Bloc de code',
              de: 'Codeblock',
              ja: 'コードブロック',
            ),
            icon: Icons.integration_instructions_rounded,
            onPressed: onCodeBlock,
          ),
          _ToolbarDivider(),
          _ToolbarButton(
            tooltip: _kbImportText(
              context,
              zh: '无序列表',
              zhHant: '無序清單',
              en: 'Bullet list',
              fr: 'Liste à puces',
              de: 'Aufzählung',
              ja: '箇条書き',
            ),
            icon: Icons.format_list_bulleted_rounded,
            onPressed: onBulletList,
          ),
          _ToolbarButton(
            tooltip: _kbImportText(
              context,
              zh: '有序列表',
              zhHant: '有序清單',
              en: 'Ordered list',
              fr: 'Liste numérotée',
              de: 'Nummerierte Liste',
              ja: '番号付きリスト',
            ),
            icon: Icons.format_list_numbered_rounded,
            onPressed: onOrderedList,
          ),
          _ToolbarButton(
            tooltip: _kbImportText(
              context,
              zh: '任务列表',
              zhHant: '任務清單',
              en: 'Task list',
              fr: 'Liste de tâches',
              de: 'Aufgabenliste',
              ja: 'タスクリスト',
            ),
            icon: Icons.checklist_rounded,
            onPressed: onTaskList,
          ),
          _ToolbarButton(
            tooltip: _kbImportText(
              context,
              zh: '引用',
              zhHant: '引用',
              en: 'Quote',
              fr: 'Citation',
              de: 'Zitat',
              ja: '引用',
            ),
            icon: Icons.format_quote_rounded,
            onPressed: onQuote,
          ),
          _ToolbarDivider(),
          _ToolbarButton(
            tooltip: _kbImportText(
              context,
              zh: '链接',
              zhHant: '連結',
              en: 'Link',
              fr: 'Lien',
              de: 'Link',
              ja: 'リンク',
            ),
            icon: Icons.link_rounded,
            onPressed: onLink,
          ),
          _ToolbarButton(
            tooltip: _kbImportText(
              context,
              zh: '图片',
              zhHant: '圖片',
              en: 'Image',
              fr: 'Image',
              de: 'Bild',
              ja: '画像',
            ),
            icon: Icons.image_outlined,
            onPressed: onImage,
          ),
          _ToolbarButton(
            tooltip: _kbImportText(
              context,
              zh: '表格',
              zhHant: '表格',
              en: 'Table',
              fr: 'Tableau',
              de: 'Tabelle',
              ja: '表',
            ),
            icon: Icons.table_chart_outlined,
            onPressed: onTable,
          ),
          _ToolbarButton(
            tooltip: _kbImportText(
              context,
              zh: '分割线',
              zhHant: '分隔線',
              en: 'Divider',
              fr: 'Séparateur',
              de: 'Trennlinie',
              ja: '区切り線',
            ),
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
  const _MarkdownTextEditor({super.key, required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      expands: true,
      maxLines: null,
      textAlignVertical: TextAlignVertical.top,
      decoration: knowledgeDialogInputDecoration(
        context,
        _kbImportText(
          context,
          zh: 'Markdown 内容',
          zhHant: 'Markdown 內容',
          en: 'Markdown content',
          fr: 'Contenu Markdown',
          de: 'Markdown-Inhalt',
          ja: 'Markdown 内容',
        ),
        alignLabelWithHint: true,
      ),
    );
  }
}

class _MarkdownPreview extends StatelessWidget {
  const _MarkdownPreview({super.key, required this.controller});

  final TextEditingController controller;

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
                _kbImportText(
                  context,
                  zh: '暂无内容可预览。',
                  zhHant: '暫無內容可預覽。',
                  en: 'Nothing to preview yet.',
                  fr: 'Aucun contenu à prévisualiser.',
                  de: 'Noch kein Inhalt für die Vorschau.',
                  ja: 'プレビューできる内容はまだありません。',
                ),
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

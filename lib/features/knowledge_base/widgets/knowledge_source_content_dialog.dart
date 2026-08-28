import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../../app/support/silent_log.dart';
import '../../../shared/db/atomic_file_operations.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/motion_durations.dart';
import '../../../shared/ui/motion_preference.dart';
import '../../../shared/ui/oh_pill.dart';
import '../../../shared/ui/openhand_clipboard.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_reveal_switcher.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../../../shared/ui/openhand_typography.dart';
import '../../../shared/util/bounded_file_io.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/date_time_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/localized_text.dart';
import '../../../shared/util/reader_file_type.dart';
import '../../../shared/util/text_search.dart';
import '../knowledge_base_controller.dart';
import '../knowledge_base_errors.dart';
import '../model/knowledge_chunk.dart';
import '../model/knowledge_source.dart';
import 'knowledge_dialog_widgets.dart';

const int _kMaxFilePreviewBytes = 2 * kBytesPerMiB;
const int _kKnowledgeEditorHistoryLimit = 160;
const double _kKnowledgeEditorInlineControlSize = 48;

Future<void> showKnowledgeSourceContentDialog(
  BuildContext context,
  String sourceId,
) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => _KnowledgeSourceContentDialog(sourceId: sourceId),
  );
}

class _KnowledgeSourceContentDialog extends StatefulWidget {
  const _KnowledgeSourceContentDialog({required this.sourceId});

  final String sourceId;

  @override
  State<_KnowledgeSourceContentDialog> createState() =>
      _KnowledgeSourceContentDialogState();
}

class _KnowledgeSourceContentDialogState
    extends State<_KnowledgeSourceContentDialog> {
  final TextEditingController _sourceController = TextEditingController();
  final TextEditingController _findController = TextEditingController();
  final TextEditingController _replaceController = TextEditingController();
  final FocusNode _editorFocusNode = FocusNode();
  final FocusNode _findFocusNode = FocusNode();
  final List<TextEditingValue> _undoStack = <TextEditingValue>[];
  final List<TextEditingValue> _redoStack = <TextEditingValue>[];
  List<int> _findMatchOffsets = const <int>[];
  TextEditingValue _lastEditValue = TextEditingValue.empty;
  bool _preview = true;
  bool _loading = true;
  bool _saving = false;
  bool _hydrating = false;
  bool _applyingHistory = false;
  bool _findVisible = false;
  bool _replaceVisible = false;
  bool _findCaseSensitive = false;
  int _currentMatchIndex = -1;
  String? _loadError;
  _KnowledgeSourceContentSnapshot? _snapshot;
  String _savedText = '';

  @override
  void initState() {
    super.initState();
    _sourceController.addListener(_onSourceChanged);
    _load();
  }

  @override
  void dispose() {
    _sourceController.dispose();
    _findController.dispose();
    _replaceController.dispose();
    _editorFocusNode.dispose();
    _findFocusNode.dispose();
    super.dispose();
  }

  void _onSourceChanged() {
    if (_hydrating || !mounted) return;
    final current = _sourceController.value;
    final textChanged = current.text != _lastEditValue.text;
    if (textChanged && !_applyingHistory) {
      _undoStack.add(_lastEditValue);
      if (_undoStack.length > _kKnowledgeEditorHistoryLimit) {
        _undoStack.removeAt(0);
      }
      _redoStack.clear();
    }
    _lastEditValue = current;
    if (textChanged && _findVisible && _findController.text.isNotEmpty) {
      _updateFindMatches(_findController.text, selectMatch: false);
      return;
    }
    if (textChanged) {
      setState(() {});
    }
  }

  Future<void> _load() async {
    try {
      final controller = context.read<KnowledgeBaseController>();
      final source = await controller.loadSource(widget.sourceId);
      final snapshot = source == null
          ? const _KnowledgeSourceContentSnapshot.missing()
          : await _KnowledgeSourceContentSnapshot.fromSource(
              source: source,
              chunks: await controller.loadChunksForSource(source.id),
            );
      if (!mounted) return;
      setState(() {
        _hydrate(snapshot);
        _loading = false;
        _loadError = null;
      });
    } catch (error, stack) {
      silentLog('knowledge_source_content_dialog', '加载知识库文档内容', error, stack);
      if (mounted) {
        setState(() {
          _loadError = knowledgeBaseFailureMessage(
            error,
            fallback: openHandLocalizedText(
              context,
              zh: '无法读取文档内容，请稍后重试。',
              zhHant: '無法讀取文件內容，請稍後重試。',
              en: 'Unable to load the document. Please try again later.',
              fr: 'Impossible de charger le document. Réessayez plus tard.',
              de: 'Das Dokument konnte nicht geladen werden. Bitte später erneut versuchen.',
              ja: 'ドキュメントを読み込めませんでした。しばらくしてから再試行してください。',
            ),
          );
          _loading = false;
        });
      }
    }
  }

  void _hydrate(_KnowledgeSourceContentSnapshot snapshot) {
    _snapshot = snapshot;
    _savedText = snapshot.text;
    _hydrating = true;
    final nextValue = TextEditingValue(
      text: snapshot.text,
      selection: const TextSelection.collapsed(offset: 0),
    );
    _sourceController.value = nextValue;
    _hydrating = false;
    _lastEditValue = nextValue;
    _undoStack.clear();
    _redoStack.clear();
    _findMatchOffsets = const <int>[];
    _currentMatchIndex = -1;
  }

  bool get _sourceMode {
    final snapshot = _snapshot;
    final source = snapshot?.source;
    if (snapshot == null || source == null) return !_preview;
    return !_supportsMarkdownPreview(source, snapshot) || !_preview;
  }

  bool get _dirty => _sourceController.text != _savedText;

  bool get _showEditActions =>
      _sourceMode && (_snapshot?.canEdit == true) && _snapshot?.source != null;

  Future<void> _saveSource() async {
    final snapshot = _snapshot;
    final path = snapshot?.editablePath;
    if (snapshot == null || path == null) {
      showOpenHandErrorSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '当前内容不可写入文件。',
          zhHant: '目前內容不可寫入檔案。',
          en: 'This content cannot be written to a file.',
          fr: 'Ce contenu ne peut pas être écrit dans un fichier.',
          de: 'Dieser Inhalt kann nicht in eine Datei geschrieben werden.',
          ja: '現在の内容はファイルに書き込めません。',
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final text = _sourceController.text;
      await writeFileAtomically(File(path), text);
      if (!mounted) return;
      setState(() {
        _savedText = text;
        _snapshot = snapshot.copyWith(
          text: text,
          loadedBytes: utf8.encode(text).length,
          lineCount: _lineCount(text),
        );
      });
      showOpenHandSuccessSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '文件已保存。',
          zhHant: '檔案已儲存。',
          en: 'File saved.',
          fr: 'Fichier enregistré.',
          de: 'Datei gespeichert.',
          ja: 'ファイルを保存しました。',
        ),
      );
    } catch (error, stack) {
      silentLog('knowledge_source_content_dialog', '保存知识库文档内容', error, stack);
      if (!mounted) return;
      final detail = knowledgeBaseFailureMessage(
        error,
        fallback: openHandLocalizedText(
          context,
          zh: '无法保存文档，请稍后重试。',
          zhHant: '無法儲存文件，請稍後重試。',
          en: 'Unable to save the document. Please try again later.',
          fr: 'Impossible d’enregistrer le document. Réessayez plus tard.',
          de: 'Das Dokument konnte nicht gespeichert werden. Bitte später erneut versuchen.',
          ja: 'ドキュメントを保存できませんでした。しばらくしてから再試行してください。',
        ),
      );
      showOpenHandErrorSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '文件保存失败：$detail',
          zhHant: '檔案儲存失敗：$detail',
          en: 'Failed to save file: $detail',
          fr: 'Échec de l’enregistrement : $detail',
          de: 'Datei konnte nicht gespeichert werden: $detail',
          ja: 'ファイルの保存に失敗しました: $detail',
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _discardSourceChanges() {
    _setEditorValue(
      TextEditingValue(
        text: _savedText,
        selection: TextSelection.collapsed(offset: _savedText.length),
      ),
      clearHistory: true,
    );
    showOpenHandInfoSnack(
      context,
      openHandLocalizedText(
        context,
        zh: '已舍弃未保存修改。',
        zhHant: '已捨棄未儲存修改。',
        en: 'Unsaved changes discarded.',
        fr: 'Modifications non enregistrées ignorées.',
        de: 'Nicht gespeicherte Änderungen verworfen.',
        ja: '未保存の変更を破棄しました。',
      ),
    );
  }

  void _setEditorValue(TextEditingValue value, {bool clearHistory = false}) {
    _hydrating = true;
    _sourceController.value = value;
    _hydrating = false;
    _lastEditValue = value;
    if (clearHistory) {
      _undoStack.clear();
      _redoStack.clear();
    }
    if (_findVisible && _findController.text.isNotEmpty) {
      _updateFindMatches(_findController.text, selectMatch: false);
    } else {
      setState(() {});
    }
  }

  void _undoEdit() {
    if (_undoStack.isEmpty) return;
    _applyingHistory = true;
    final current = _sourceController.value;
    final previous = _undoStack.removeLast();
    _redoStack.add(current);
    _setEditorValue(previous);
    _applyingHistory = false;
  }

  void _redoEdit() {
    if (_redoStack.isEmpty) return;
    _applyingHistory = true;
    final current = _sourceController.value;
    final next = _redoStack.removeLast();
    _undoStack.add(current);
    _setEditorValue(next);
    _applyingHistory = false;
  }

  void _showFind({bool replace = false}) {
    setState(() {
      _preview = false;
      _findVisible = true;
      _replaceVisible = replace;
    });
    _updateFindMatches(_findController.text, selectMatch: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _findFocusNode.requestFocus();
    });
  }

  void _hideFind() {
    setState(() {
      _findVisible = false;
      _replaceVisible = false;
      _findMatchOffsets = const <int>[];
      _currentMatchIndex = -1;
    });
  }

  void _updateFindMatches(
    String query, {
    bool selectMatch = true,
    bool focusEditor = false,
  }) {
    if (query.isEmpty) {
      setState(() {
        _findMatchOffsets = const <int>[];
        _currentMatchIndex = -1;
      });
      return;
    }
    final offsets = findTextMatchOffsets(
      text: _sourceController.text,
      query: query,
      caseSensitive: _findCaseSensitive,
      allowOverlapping: false,
    );
    final selectionBase = _sourceController.selection.baseOffset;
    var selectedIndex = offsets.isEmpty ? -1 : 0;
    if (offsets.isNotEmpty && selectionBase >= 0) {
      final nearest = offsets.indexWhere((offset) => offset >= selectionBase);
      selectedIndex = nearest < 0 ? 0 : nearest;
    }
    setState(() {
      _findMatchOffsets = offsets;
      _currentMatchIndex = selectedIndex;
    });
    if (selectMatch && selectedIndex >= 0) {
      _selectMatch(selectedIndex, requestFocus: focusEditor);
    }
  }

  void _findNext() {
    if (_findMatchOffsets.isEmpty) return;
    final next = (_currentMatchIndex + 1) % _findMatchOffsets.length;
    setState(() => _currentMatchIndex = next);
    _selectMatch(next);
  }

  void _findPrevious() {
    if (_findMatchOffsets.isEmpty) return;
    final previous =
        (_currentMatchIndex - 1 + _findMatchOffsets.length) %
        _findMatchOffsets.length;
    setState(() => _currentMatchIndex = previous);
    _selectMatch(previous);
  }

  void _selectMatch(int index, {bool requestFocus = true}) {
    if (index < 0 || index >= _findMatchOffsets.length) return;
    final offset = _findMatchOffsets[index];
    final length = _findController.text.length;
    _sourceController.selection = TextSelection(
      baseOffset: offset,
      extentOffset: math.min(offset + length, _sourceController.text.length),
    );
    if (requestFocus) {
      _editorFocusNode.requestFocus();
    }
  }

  void _toggleFindCaseSensitive() {
    setState(() => _findCaseSensitive = !_findCaseSensitive);
    _updateFindMatches(_findController.text);
  }

  void _replaceCurrent() {
    final snapshot = _snapshot;
    if (snapshot?.canEdit != true ||
        _currentMatchIndex < 0 ||
        _currentMatchIndex >= _findMatchOffsets.length ||
        _findController.text.isEmpty) {
      return;
    }
    final offset = _findMatchOffsets[_currentMatchIndex];
    final findLength = _findController.text.length;
    final replacement = _replaceController.text;
    final text = _sourceController.text;
    if (offset + findLength > text.length) return;
    _sourceController.value = TextEditingValue(
      text: text.replaceRange(offset, offset + findLength, replacement),
      selection: TextSelection.collapsed(offset: offset + replacement.length),
    );
    _updateFindMatches(_findController.text);
  }

  void _replaceAll() {
    final snapshot = _snapshot;
    final findText = _findController.text;
    if (snapshot?.canEdit != true || findText.isEmpty) return;
    final replacement = _replaceController.text;
    final current = _sourceController.text;
    final next = _findCaseSensitive
        ? current.replaceAll(findText, replacement)
        : current.replaceAll(
            RegExp(RegExp.escape(findText), caseSensitive: false),
            replacement,
          );
    if (next == current) return;
    final selectionOffset = math.max(0, _sourceController.selection.baseOffset);
    _sourceController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(
        offset: math.min(next.length, selectionOffset),
      ),
    );
    _updateFindMatches(findText, selectMatch: false);
  }

  _KnowledgeEditorControls _editorControls() {
    return _KnowledgeEditorControls(
      sourceMode: _sourceMode,
      editable: _snapshot?.canEdit == true,
      canUndo: _undoStack.isNotEmpty,
      canRedo: _redoStack.isNotEmpty,
      findVisible: _findVisible,
      replaceVisible: _replaceVisible,
      findCaseSensitive: _findCaseSensitive,
      currentMatchIndex: _currentMatchIndex,
      matchCount: _findMatchOffsets.length,
      findController: _findController,
      replaceController: _replaceController,
      findFocusNode: _findFocusNode,
      editorFocusNode: _editorFocusNode,
      onUndo: _undoEdit,
      onRedo: _redoEdit,
      onShowFind: () => _showFind(),
      onShowReplace: () => _showFind(replace: true),
      onHideFind: _hideFind,
      onFindChanged: (value) => _updateFindMatches(value),
      onFindNext: _findNext,
      onFindPrevious: _findPrevious,
      onToggleCaseSensitive: _toggleFindCaseSensitive,
      onReplaceCurrent: _replaceCurrent,
      onReplaceAll: _replaceAll,
    );
  }

  @override
  Widget build(BuildContext context) {
    final dialogHeight = math.min(
      MediaQuery.sizeOf(context).height * 0.82,
      760.0,
    );
    final snapshot = _snapshot;
    return buildOpenHandAlertDialog(
      title: Text(
        openHandLocalizedText(
          context,
          zh: '查看知识库文档',
          zhHant: '查看知識庫文件',
          en: 'View Knowledge Source',
          fr: 'Voir la source de connaissance',
          de: 'Wissensquelle anzeigen',
          ja: 'ナレッジソースを表示',
        ),
      ),
      content: buildOpenHandDialogConstrainedContent(
        width: 980,
        height: dialogHeight,
        child: OpenHandContentStateSwitcher(
          // 外层 SizedBox 已定高，这里只做淡入淡出。
          animateSize: false,
          stateKey: _loading
              ? 'loading'
              : _loadError != null
              ? 'error'
              : snapshot?.source == null
              ? 'missing'
              : 'content',
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _loadError != null
              ? KnowledgeDialogNotice(
                  icon: Icons.error_outline_rounded,
                  message: openHandLocalizedText(
                    context,
                    zh: '文档内容加载失败：$_loadError',
                    zhHant: '文件內容載入失敗：$_loadError',
                    en: 'Failed to load document content: $_loadError',
                    fr: 'Échec du chargement du contenu : $_loadError',
                    de: 'Dokumentinhalt konnte nicht geladen werden: $_loadError',
                    ja: 'ドキュメント内容の読み込みに失敗しました: $_loadError',
                  ),
                  error: true,
                )
              : snapshot?.source == null
              ? KnowledgeDialogNotice(
                  icon: Icons.info_outline_rounded,
                  message: knowledgeSourceMissingMessage(context),
                )
              : _KnowledgeSourceContentBody(
                  snapshot: snapshot!,
                  contentController: _sourceController,
                  preview: _preview,
                  editable: _showEditActions,
                  editorControls: _editorControls(),
                  onPreviewChanged: (value) => setState(() => _preview = value),
                ),
        ),
      ),
      actions: [
        if (_showEditActions)
          OpenHandDialogActionButton.secondary(
            onPressed: _saving || !_dirty ? null : _discardSourceChanges,
            icon: Icons.undo_rounded,
            label: openHandLocalizedText(
              context,
              zh: '舍弃修改',
              zhHant: '捨棄修改',
              en: 'Discard',
              fr: 'Ignorer',
              de: 'Verwerfen',
              ja: '破棄',
            ),
          ),
        if (_showEditActions)
          OpenHandDialogActionButton.primary(
            onPressed: _saving || !_dirty ? null : _saveSource,
            icon: Icons.save_rounded,
            busy: _saving,
            label: openHandLocalizedText(
              context,
              zh: '保存文件',
              zhHant: '儲存檔案',
              en: 'Save File',
              fr: 'Enregistrer',
              de: 'Datei speichern',
              ja: 'ファイルを保存',
            ),
          ),
        OpenHandDialogActionButton.secondary(
          onPressed: snapshot?.source == null
              ? null
              : () async {
                  await copyOpenHandTextToClipboard(
                    logTag: 'knowledge_base',
                    context: context,
                    text: snapshot!.source!.originalPath,
                    successMessage: knowledgePathCopiedMessage(context),
                    logAction: '复制知识源路径',
                  );
                },
          icon: Icons.copy_rounded,
          label: knowledgeCopyPathLabel(context),
        ),
        OpenHandDialogActionButton.primary(
          onPressed: () => Navigator.of(context).pop(),
          label: openHandCloseLabel(context),
        ),
      ],
    );
  }
}

class _KnowledgeEditorControls {
  const _KnowledgeEditorControls({
    required this.sourceMode,
    required this.editable,
    required this.canUndo,
    required this.canRedo,
    required this.findVisible,
    required this.replaceVisible,
    required this.findCaseSensitive,
    required this.currentMatchIndex,
    required this.matchCount,
    required this.findController,
    required this.replaceController,
    required this.findFocusNode,
    required this.editorFocusNode,
    required this.onUndo,
    required this.onRedo,
    required this.onShowFind,
    required this.onShowReplace,
    required this.onHideFind,
    required this.onFindChanged,
    required this.onFindNext,
    required this.onFindPrevious,
    required this.onToggleCaseSensitive,
    required this.onReplaceCurrent,
    required this.onReplaceAll,
  });

  final bool sourceMode;
  final bool editable;
  final bool canUndo;
  final bool canRedo;
  final bool findVisible;
  final bool replaceVisible;
  final bool findCaseSensitive;
  final int currentMatchIndex;
  final int matchCount;
  final TextEditingController findController;
  final TextEditingController replaceController;
  final FocusNode findFocusNode;
  final FocusNode editorFocusNode;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onShowFind;
  final VoidCallback onShowReplace;
  final VoidCallback onHideFind;
  final ValueChanged<String> onFindChanged;
  final VoidCallback onFindNext;
  final VoidCallback onFindPrevious;
  final VoidCallback onToggleCaseSensitive;
  final VoidCallback onReplaceCurrent;
  final VoidCallback onReplaceAll;
}

class _KnowledgeModeToggle extends StatelessWidget {
  const _KnowledgeModeToggle({required this.preview, required this.onChanged});

  final bool preview;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.68),
        borderRadius: kOpenHandPillBorderRadius,
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _KnowledgeModeToggleButton(
            selected: preview,
            icon: Icons.visibility_outlined,
            label: knowledgePreviewLabel(context),
            onPressed: () => onChanged(true),
          ),
          Container(width: 1, color: colorScheme.outlineVariant),
          _KnowledgeModeToggleButton(
            selected: !preview,
            icon: Icons.code_rounded,
            label: openHandLocalizedText(
              context,
              zh: '源码',
              zhHant: '原始碼',
              en: 'Source',
              fr: 'Source',
              de: 'Quelle',
              ja: 'ソース',
            ),
            onPressed: () => onChanged(false),
          ),
        ],
      ),
    );
  }
}

class _KnowledgeModeToggleButton extends StatelessWidget {
  const _KnowledgeModeToggleButton({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final foreground = selected
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurfaceVariant;
    return Material(
      color: selected ? colorScheme.primaryContainer : Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          height: 48,
          width: 94,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: foreground),
              kOpenHandHGap7,
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KnowledgeEditorToolbar extends StatelessWidget {
  const _KnowledgeEditorToolbar({required this.controls});

  final _KnowledgeEditorControls controls;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _KnowledgeEditorToolButton(
          tooltip: knowledgeUndoLabel(context),
          icon: Icons.undo_rounded,
          onPressed: controls.canUndo ? controls.onUndo : null,
        ),
        _KnowledgeEditorToolButton(
          tooltip: knowledgeRedoLabel(context),
          icon: Icons.redo_rounded,
          onPressed: controls.canRedo ? controls.onRedo : null,
        ),
        _KnowledgeEditorToolButton(
          tooltip: _knowledgeSourcFindLabel(context),
          icon: Icons.search_rounded,
          onPressed: controls.onShowFind,
        ),
        _KnowledgeEditorToolButton(
          tooltip: openHandLocalizedText(
            context,
            zh: '查找并替换',
            zhHant: '尋找並取代',
            en: 'Find and replace',
            fr: 'Rechercher et remplacer',
            de: 'Suchen und ersetzen',
            ja: '検索と置換',
          ),
          icon: Icons.find_replace_rounded,
          onPressed: controls.editable ? controls.onShowReplace : null,
        ),
      ],
    );
  }
}

class _KnowledgeFindReplaceBar extends StatelessWidget {
  const _KnowledgeFindReplaceBar({required this.controls});

  final _KnowledgeEditorControls controls;

  @override
  Widget build(BuildContext context) {
    final matchLabel = controls.matchCount <= 0
        ? ''
        : '${controls.currentMatchIndex + 1}/${controls.matchCount}';
    final findActions = <Widget>[
      _KnowledgeEditorToolButton(
        tooltip: openHandLocalizedText(
          context,
          zh: '上一个匹配项',
          zhHant: '上一個符合項',
          en: 'Previous match',
          fr: 'Correspondance précédente',
          de: 'Vorheriger Treffer',
          ja: '前の一致',
        ),
        icon: Icons.keyboard_arrow_up_rounded,
        onPressed: controls.matchCount <= 0 ? null : controls.onFindPrevious,
      ),
      _KnowledgeEditorToolButton(
        tooltip: openHandLocalizedText(
          context,
          zh: '下一个匹配项',
          zhHant: '下一個符合項',
          en: 'Next match',
          fr: 'Correspondance suivante',
          de: 'Nächster Treffer',
          ja: '次の一致',
        ),
        icon: Icons.keyboard_arrow_down_rounded,
        onPressed: controls.matchCount <= 0 ? null : controls.onFindNext,
      ),
      _KnowledgeEditorToolButton(
        tooltip: openHandLocalizedText(
          context,
          zh: '区分大小写',
          zhHant: '區分大小寫',
          en: 'Match case',
          fr: 'Respecter la casse',
          de: 'Groß-/Kleinschreibung beachten',
          ja: '大文字小文字を区別',
        ),
        icon: Icons.font_download_rounded,
        selected: controls.findCaseSensitive,
        onPressed: controls.onToggleCaseSensitive,
      ),
      if (!controls.replaceVisible)
        _KnowledgeEditorToolButton(
          tooltip: openHandLocalizedText(
            context,
            zh: '显示替换',
            zhHant: '顯示取代',
            en: 'Show replace',
            fr: 'Afficher remplacer',
            de: 'Ersetzen anzeigen',
            ja: '置換を表示',
          ),
          icon: Icons.find_replace_rounded,
          onPressed: controls.editable ? controls.onShowReplace : null,
        ),
      _KnowledgeEditorToolButton(
        tooltip: openHandLocalizedText(
          context,
          zh: '关闭查找',
          zhHant: '關閉尋找',
          en: 'Close find',
          fr: 'Fermer la recherche',
          de: 'Suche schließen',
          ja: '検索を閉じる',
        ),
        icon: Icons.close_rounded,
        onPressed: controls.onHideFind,
      ),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: _KnowledgeFindTextField(
                controller: controls.findController,
                focusNode: controls.findFocusNode,
                hintText: _knowledgeSourcFindLabel(context),
                onChanged: controls.onFindChanged,
                onSubmitted: (_) => controls.onFindNext(),
              ),
            ),
            if (matchLabel.isNotEmpty) ...[
              kOpenHandHGap10,
              Text(
                matchLabel,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            kOpenHandHGap12,
            _KnowledgeEditorToolButtonGroup(children: findActions),
          ],
        ),
        if (controls.replaceVisible) ...[
          kOpenHandGap10,
          Row(
            children: [
              Expanded(
                child: _KnowledgeFindTextField(
                  controller: controls.replaceController,
                  hintText: openHandLocalizedText(
                    context,
                    zh: '替换为',
                    zhHant: '取代為',
                    en: 'Replace with',
                    fr: 'Remplacer par',
                    de: 'Ersetzen durch',
                    ja: '置換後',
                  ),
                  onSubmitted: (_) => controls.onReplaceCurrent(),
                ),
              ),
              kOpenHandHGap12,
              _KnowledgeEditorToolButtonGroup(
                children: [
                  _KnowledgeEditorToolButton(
                    tooltip: openHandLocalizedText(
                      context,
                      zh: '替换当前项',
                      zhHant: '取代目前項',
                      en: 'Replace current',
                      fr: 'Remplacer l’élément actuel',
                      de: 'Aktuellen Treffer ersetzen',
                      ja: '現在の一致を置換',
                    ),
                    icon: Icons.find_replace_rounded,
                    onPressed: controls.editable && controls.matchCount > 0
                        ? controls.onReplaceCurrent
                        : null,
                  ),
                  _KnowledgeEditorToolButton(
                    tooltip: openHandLocalizedText(
                      context,
                      zh: '全部替换',
                      zhHant: '全部取代',
                      en: 'Replace all',
                      fr: 'Tout remplacer',
                      de: 'Alle ersetzen',
                      ja: 'すべて置換',
                    ),
                    icon: Icons.done_all_rounded,
                    onPressed: controls.editable && controls.matchCount > 0
                        ? controls.onReplaceAll
                        : null,
                  ),
                ],
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _KnowledgeFindTextField extends StatelessWidget {
  const _KnowledgeFindTextField({
    required this.controller,
    required this.hintText,
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: _kKnowledgeEditorInlineControlSize,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        textAlignVertical: TextAlignVertical.center,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: hintText,
          isDense: true,
          filled: true,
          fillColor: colorScheme.surface,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 10,
          ),
          border: const OutlineInputBorder(
            borderRadius: kOpenHandBorderRadius10,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: kOpenHandBorderRadius10,
            borderSide: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.84),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: kOpenHandBorderRadius10,
            borderSide: BorderSide(color: colorScheme.primary, width: 1.4),
          ),
        ),
      ),
    );
  }
}

class _KnowledgeEditorToolButtonGroup extends StatelessWidget {
  const _KnowledgeEditorToolButtonGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }
}

class _KnowledgeEditorToolButton extends StatelessWidget {
  const _KnowledgeEditorToolButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.selected = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: IconButton.filledTonal(
        onPressed: onPressed,
        icon: Icon(icon),
        iconSize: 18,
        constraints: const BoxConstraints.tightFor(
          width: _kKnowledgeEditorInlineControlSize,
          height: _kKnowledgeEditorInlineControlSize,
        ),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(
          minimumSize: const Size.square(_kKnowledgeEditorInlineControlSize),
          fixedSize: const Size.square(_kKnowledgeEditorInlineControlSize),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          backgroundColor: selected ? colorScheme.primaryContainer : null,
          foregroundColor: selected ? colorScheme.onPrimaryContainer : null,
        ),
      ),
    );
  }
}

class _KnowledgeSourceContentBody extends StatelessWidget {
  const _KnowledgeSourceContentBody({
    required this.snapshot,
    required this.contentController,
    required this.preview,
    required this.editable,
    required this.editorControls,
    required this.onPreviewChanged,
  });

  final _KnowledgeSourceContentSnapshot snapshot;
  final TextEditingController contentController;
  final bool preview;
  final bool editable;
  final _KnowledgeEditorControls editorControls;
  final ValueChanged<bool> onPreviewChanged;

  @override
  Widget build(BuildContext context) {
    final source = snapshot.source!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final previewAvailable = _supportsMarkdownPreview(source, snapshot);
    final showPreview = previewAvailable && preview;
    final text = contentController.text;
    final lineCount = _lineCount(text);
    final byteCount = utf8.encode(text).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _KnowledgeViewerPanel(
          margin: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHigh,
                      borderRadius: kOpenHandBorderRadius12,
                    ),
                    child: Icon(
                      knowledgeSourceKindIcon(source.kind),
                      color: colorScheme.primary,
                      size: 22,
                    ),
                  ),
                  kOpenHandHGap12,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          source.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        kOpenHandGap4,
                        Text(
                          snapshot.path.isEmpty
                              ? source.originalPath
                              : snapshot.path,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              kOpenHandGap14,
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  KnowledgeDialogChip(
                    icon: Icons.category_outlined,
                    label: localizedKnowledgeSourceKind(context, source.kind),
                  ),
                  KnowledgeDialogChip(
                    icon: Icons.sd_storage_outlined,
                    label: formatByteSize(source.sizeBytes),
                  ),
                  KnowledgeDialogChip(
                    icon: snapshot.loadedFromFile
                        ? Icons.insert_drive_file_outlined
                        : Icons.view_agenda_outlined,
                    label: snapshot.loadedFromFile
                        ? openHandLocalizedText(
                            context,
                            zh: '原文',
                            zhHant: '原文',
                            en: 'Original',
                            fr: 'Original',
                            de: 'Original',
                            ja: '原文',
                          )
                        : openHandLocalizedText(
                            context,
                            zh: '索引内容',
                            zhHant: '索引內容',
                            en: 'Indexed content',
                            fr: 'Contenu indexé',
                            de: 'Indexierter Inhalt',
                            ja: 'インデックス済み内容',
                          ),
                  ),
                  KnowledgeDialogChip(
                    icon: Icons.schedule_rounded,
                    label: formatYearMonthDayHmLocal(source.updatedAt),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (snapshot.notice != null) ...[
          KnowledgeDialogNotice(
            icon: Icons.info_outline_rounded,
            message: _localizedNotice(snapshot.notice!, context),
            tone: KnowledgeDialogNoticeTone.warning,
          ),
          kOpenHandGap10,
        ],
        _KnowledgeViewerPanel(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          margin: const EdgeInsets.only(bottom: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 48,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (previewAvailable)
                      _KnowledgeModeToggle(
                        preview: preview,
                        onChanged: onPreviewChanged,
                      ),
                    if (previewAvailable) kOpenHandHGap8,
                    SizedBox(
                      height: 48,
                      child: FilledButton.tonalIcon(
                        onPressed: text.trim().isEmpty
                            ? null
                            : () async {
                                await copyOpenHandTextToClipboard(
                                  logTag: 'knowledge_base',
                                  context: context,
                                  text: text,
                                  successMessage: openHandLocalizedText(
                                    context,
                                    zh: '内容已复制。',
                                    zhHant: '內容已複製。',
                                    en: 'Content copied.',
                                    fr: 'Contenu copié.',
                                    de: 'Inhalt kopiert.',
                                    ja: '内容をコピーしました。',
                                  ),
                                  logAction: '复制知识源内容',
                                );
                              },
                        icon: const Icon(Icons.copy_all_rounded),
                        label: Text(knowledgeCopyContentLabel(context)),
                        style: FilledButton.styleFrom(
                          visualDensity: const VisualDensity(
                            horizontal: -1,
                            vertical: -1,
                          ),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ),
                    kOpenHandHGap12,
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          openHandLocalizedText(
                            context,
                            zh: '$lineCount 行 · ${formatByteSize(byteCount)}',
                            zhHant:
                                '$lineCount 行 · ${formatByteSize(byteCount)}',
                            en: '$lineCount lines · ${formatByteSize(byteCount)}',
                            fr: '$lineCount lignes · ${formatByteSize(byteCount)}',
                            de: '$lineCount Zeilen · ${formatByteSize(byteCount)}',
                            ja: '$lineCount 行 · ${formatByteSize(byteCount)}',
                          ),
                          textAlign: TextAlign.right,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (editorControls.sourceMode) ...[
                kOpenHandGap8,
                _KnowledgeEditorToolbar(controls: editorControls),
              ],
              if (editorControls.sourceMode && editorControls.findVisible) ...[
                kOpenHandGap8,
                _KnowledgeFindReplaceBar(controls: editorControls),
              ],
            ],
          ),
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: openHandMotionDuration(context, kOpenHandMotion180),
            switchInCurve: kOpenHandSwitchInCurve,
            switchOutCurve: kOpenHandSwitchOutCurve,
            child: showPreview
                ? _KnowledgeMarkdownViewer(
                    key: const ValueKey<String>('markdown-preview'),
                    text: text,
                  )
                : _KnowledgeSourceTextViewer(
                    key: const ValueKey<String>('source-view'),
                    controller: contentController,
                    focusNode: editorControls.editorFocusNode,
                    editable: editable,
                    emptyText: openHandLocalizedText(
                      context,
                      zh: '暂无可浏览内容。',
                      zhHant: '暫無可瀏覽內容。',
                      en: 'No content to view.',
                      fr: 'Aucun contenu à afficher.',
                      de: 'Kein Inhalt zum Anzeigen.',
                      ja: '表示できる内容はありません。',
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _KnowledgeViewerPanel extends StatelessWidget {
  const _KnowledgeViewerPanel({
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.margin = EdgeInsets.zero,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: _knowledgeViewerPanelDecoration(context),
      child: child,
    );
  }
}

BoxDecoration _knowledgeViewerPanelDecoration(BuildContext context) {
  final colorScheme = Theme.of(context).colorScheme;
  return BoxDecoration(
    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.46),
    borderRadius: kOpenHandBorderRadius14,
    border: Border.all(
      color: colorScheme.outlineVariant.withValues(alpha: 0.72),
    ),
  );
}

class _KnowledgeMarkdownViewer extends StatelessWidget {
  const _KnowledgeMarkdownViewer({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _knowledgeViewerPanelDecoration(context),
      child: Markdown(
        data: text.trim(),
        selectable: true,
        softLineBreak: true,
        extensionSet: md.ExtensionSet.gitHubFlavored,
        padding: const EdgeInsets.all(14),
        styleSheet: knowledgeMarkdownStyleSheet(context),
      ),
    );
  }
}

class _KnowledgeSourceTextViewer extends StatelessWidget {
  const _KnowledgeSourceTextViewer({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.editable,
    required this.emptyText,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool editable;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      decoration: _knowledgeViewerPanelDecoration(context),
      child: editable
          ? TextField(
              controller: controller,
              focusNode: focusNode,
              expands: true,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              textAlignVertical: TextAlignVertical.top,
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(14),
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: kOpenHandMonospaceFontFamily,
                height: 1.42,
                color: colorScheme.onSurface,
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(14),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SelectableText(
                  controller.text.trim().isEmpty
                      ? emptyText
                      : _withLineNumbers(controller.text),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: kOpenHandMonospaceFontFamily,
                    height: 1.42,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
            ),
    );
  }

  String _withLineNumbers(String raw) {
    final lines = raw.split('\n');
    final width = lines.length.toString().length;
    return [
      for (var i = 0; i < lines.length; i++)
        '${(i + 1).toString().padLeft(width)}  ${lines[i]}',
    ].join('\n');
  }
}

class _KnowledgeSourceContentSnapshot {
  const _KnowledgeSourceContentSnapshot.missing()
    : source = null,
      text = '',
      path = '',
      editablePath = null,
      notice = null,
      loadedFromFile = false,
      canEdit = false,
      loadedBytes = 0,
      lineCount = 0;

  const _KnowledgeSourceContentSnapshot({
    required this.source,
    required this.text,
    required this.path,
    required this.editablePath,
    required this.notice,
    required this.loadedFromFile,
    required this.canEdit,
    required this.loadedBytes,
    required this.lineCount,
  });

  final KnowledgeSource? source;
  final String text;
  final String path;
  final String? editablePath;
  final _KnowledgeSourceContentNotice? notice;
  final bool loadedFromFile;
  final bool canEdit;
  final int loadedBytes;
  final int lineCount;

  _KnowledgeSourceContentSnapshot copyWith({
    String? text,
    int? loadedBytes,
    int? lineCount,
  }) {
    return _KnowledgeSourceContentSnapshot(
      source: source,
      text: text ?? this.text,
      path: path,
      editablePath: editablePath,
      notice: notice,
      loadedFromFile: loadedFromFile,
      canEdit: canEdit,
      loadedBytes: loadedBytes ?? this.loadedBytes,
      lineCount: lineCount ?? this.lineCount,
    );
  }

  static Future<_KnowledgeSourceContentSnapshot> fromSource({
    required KnowledgeSource source,
    required List<KnowledgeChunk> chunks,
  }) async {
    final preferredFile = await _resolveReadableFile(source);
    if (preferredFile != null && _shouldReadFile(source)) {
      try {
        final stat = await preferredFile.stat().timeout(
          defaultBoundedFileReadIdleTimeout,
        );
        final truncated = stat.size > _kMaxFilePreviewBytes;
        final bytes = await _readPreviewBytes(preferredFile);
        final text = utf8.decode(bytes, allowMalformed: true);
        return _KnowledgeSourceContentSnapshot(
          source: source,
          text: text,
          path: preferredFile.path,
          editablePath: truncated ? null : preferredFile.path,
          loadedFromFile: true,
          canEdit: !truncated,
          loadedBytes: bytes.length,
          lineCount: _lineCount(text),
          notice: truncated
              ? _KnowledgeSourceContentNotice.largeFileTruncated
              : null,
        );
      } catch (_) {
        // 文件读取失败时回退到已索引分块。
      }
    }

    final text = _chunksToText(chunks);
    return _KnowledgeSourceContentSnapshot(
      source: source,
      text: text,
      path: preferredFile?.path ?? source.originalPath,
      editablePath: null,
      loadedFromFile: false,
      canEdit: false,
      loadedBytes: utf8.encode(text).length,
      lineCount: _lineCount(text),
      notice: text.trim().isEmpty
          ? _KnowledgeSourceContentNotice.empty
          : _KnowledgeSourceContentNotice.indexedFallback,
    );
  }
}

enum _KnowledgeSourceContentNotice {
  largeFileTruncated,
  indexedFallback,
  empty,
}

Future<File?> _resolveReadableFile(KnowledgeSource source) async {
  final candidates = stringListFromValue(<String>[
    source.storedPath,
    source.originalPath,
  ]).toSet();
  for (final path in candidates) {
    final file = File(path);
    if (await isRegularFilePath(file.path, followLinks: true)) return file;
  }
  return null;
}

bool _shouldReadFile(KnowledgeSource source) {
  final kind = source.kind.trim().toLowerCase();
  if (const <String>{
    'markdown',
    'text',
    'code',
    'html',
    'table',
    'structured',
    'note',
  }.contains(kind)) {
    return true;
  }
  return ReaderFileType.isTextLikeExtension(p.extension(source.originalPath));
}

Future<Uint8List> _readPreviewBytes(File file) {
  return readBoundedFilePrefixBytes(file, maxBytes: _kMaxFilePreviewBytes);
}

String _chunksToText(List<KnowledgeChunk> chunks) {
  final buffer = StringBuffer();
  for (final chunk in chunks) {
    final heading = chunk.headingPath.trim().isNotEmpty
        ? chunk.headingPath.trim()
        : chunk.title.trim();
    if (heading.isNotEmpty) {
      buffer.writeln('## $heading');
      buffer.writeln();
    }
    buffer.writeln(chunk.content.trimRight());
    buffer.writeln();
    buffer.writeln('---');
    buffer.writeln();
  }
  final text = buffer.toString().trimRight();
  return text.endsWith('---')
      ? text.substring(0, text.length - 3).trimRight()
      : text;
}

bool _supportsMarkdownPreview(
  KnowledgeSource source,
  _KnowledgeSourceContentSnapshot snapshot,
) {
  if (!snapshot.loadedFromFile) return true;
  final kind = source.kind.trim().toLowerCase();
  if (const <String>{
    'markdown',
    'html',
    'table',
    'structured',
    'note',
  }.contains(kind)) {
    return true;
  }
  final extension = p
      .extension(snapshot.path.isEmpty ? source.originalPath : snapshot.path)
      .replaceFirst('.', '')
      .trim()
      .toLowerCase();
  return const <String>{
    'md',
    'markdown',
    'html',
    'htm',
    'csv',
    'json',
    'toml',
    'yaml',
    'yml',
  }.contains(extension);
}

String _localizedNotice(
  _KnowledgeSourceContentNotice notice,
  BuildContext context,
) {
  return switch (notice) {
    _KnowledgeSourceContentNotice.largeFileTruncated => openHandLocalizedText(
      context,
      zh: '文件较大，当前仅预览前 ${formatByteSize(_kMaxFilePreviewBytes)}。',
      zhHant: '檔案較大，目前僅預覽前 ${formatByteSize(_kMaxFilePreviewBytes)}。',
      en: 'The file is large. Showing only the first ${formatByteSize(_kMaxFilePreviewBytes)}.',
      fr: 'Le fichier est volumineux. Seuls les ${formatByteSize(_kMaxFilePreviewBytes)} premiers sont affichés.',
      de: 'Die Datei ist groß. Es werden nur die ersten ${formatByteSize(_kMaxFilePreviewBytes)} angezeigt.',
      ja: 'ファイルが大きいため、先頭 ${formatByteSize(_kMaxFilePreviewBytes)} のみ表示しています。',
    ),
    _KnowledgeSourceContentNotice.indexedFallback => openHandLocalizedText(
      context,
      zh: '当前展示已索引的分块内容；原文件不可直接作为文本浏览。',
      zhHant: '目前顯示已索引的分塊內容；原始檔案無法直接以文字瀏覽。',
      en: 'Showing indexed chunks because the original file cannot be viewed directly as text.',
      fr: 'Affichage des fragments indexés, car le fichier d’origine ne peut pas être affiché directement en texte.',
      de: 'Indexierte Abschnitte werden angezeigt, da die Originaldatei nicht direkt als Text angezeigt werden kann.',
      ja: '元ファイルをテキストとして直接表示できないため、インデックス済みチャンクを表示しています。',
    ),
    _KnowledgeSourceContentNotice.empty => openHandLocalizedText(
      context,
      zh: '没有可浏览的原文或索引内容。',
      zhHant: '沒有可瀏覽的原文或索引內容。',
      en: 'No original or indexed content is available to view.',
      fr: 'Aucun contenu original ou indexé n’est disponible.',
      de: 'Es ist kein Original- oder indexierter Inhalt verfügbar.',
      ja: '表示できる原文またはインデックス済み内容はありません。',
    ),
  };
}

int _lineCount(String text) {
  if (text.isEmpty) return 0;
  return '\n'.allMatches(text).length + 1;
}

// 本文件内复用文案。

String _knowledgeSourcFindLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '查找',
    zhHant: '尋找',
    en: 'Find',
    fr: 'Rechercher',
    de: 'Suchen',
    ja: '検索',
  );
}

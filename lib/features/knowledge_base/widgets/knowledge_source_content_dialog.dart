import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/date_time_format.dart';
import '../../../shared/util/localized_text.dart';
import '../knowledge_base_controller.dart';
import '../model/knowledge_chunk.dart';
import '../model/knowledge_source.dart';
import 'knowledge_dialog_widgets.dart';

const int _kMaxFilePreviewBytes = 2 * kBytesPerMiB;

Future<void> showKnowledgeSourceContentDialog(
  BuildContext context,
  String sourceId,
) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => KnowledgeSourceContentDialog(sourceId: sourceId),
  );
}

class KnowledgeSourceContentDialog extends StatefulWidget {
  const KnowledgeSourceContentDialog({super.key, required this.sourceId});

  final String sourceId;

  @override
  State<KnowledgeSourceContentDialog> createState() =>
      _KnowledgeSourceContentDialogState();
}

class _KnowledgeSourceContentDialogState
    extends State<KnowledgeSourceContentDialog> {
  late final Future<_KnowledgeSourceContentSnapshot> _future = _load();
  bool _preview = true;

  Future<_KnowledgeSourceContentSnapshot> _load() async {
    final controller = context.read<KnowledgeBaseController>();
    final source = await controller.loadSource(widget.sourceId);
    if (source == null) return const _KnowledgeSourceContentSnapshot.missing();
    final chunks = await controller.loadChunksForSource(source.id);
    return _KnowledgeSourceContentSnapshot.fromSource(
      source: source,
      chunks: chunks,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isZh = openHandIsChineseLocale(context);
    final dialogHeight = math.min(
      MediaQuery.sizeOf(context).height * 0.82,
      760.0,
    );
    return buildOpenHandAlertDialog(
      title: Text(isZh ? '查看知识库文档' : 'View Knowledge Source'),
      content: buildOpenHandDialogConstrainedContent(
        width: 980,
        height: dialogHeight,
        child: FutureBuilder<_KnowledgeSourceContentSnapshot>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return KnowledgeDialogNotice(
                icon: Icons.error_outline_rounded,
                message: isZh
                    ? '文档内容加载失败：${snapshot.error}'
                    : 'Failed to load document content: ${snapshot.error}',
                error: true,
              );
            }
            final data = snapshot.data;
            if (data == null || data.source == null) {
              return KnowledgeDialogNotice(
                icon: Icons.info_outline_rounded,
                message: isZh ? '来源不存在。' : 'Source not found.',
              );
            }
            return _KnowledgeSourceContentBody(
              snapshot: data,
              preview: _preview,
              onPreviewChanged: (value) => setState(() => _preview = value),
            );
          },
        ),
      ),
      actions: [
        FutureBuilder<_KnowledgeSourceContentSnapshot>(
          future: _future,
          builder: (context, snapshot) {
            final source = snapshot.data?.source;
            return OpenHandDialogActionButton.secondary(
              onPressed: source == null
                  ? null
                  : () {
                      Clipboard.setData(
                        ClipboardData(text: source.originalPath),
                      );
                      OpenHandSnackBar.showSuccess(
                        context,
                        isZh ? '路径已复制。' : 'Path copied.',
                      );
                    },
              icon: Icons.copy_rounded,
              label: isZh ? '复制路径' : 'Copy Path',
            );
          },
        ),
        OpenHandDialogActionButton.primary(
          onPressed: () => Navigator.of(context).pop(),
          label: isZh ? '关闭' : 'Close',
        ),
      ],
    );
  }
}

class _KnowledgeSourceContentBody extends StatelessWidget {
  const _KnowledgeSourceContentBody({
    required this.snapshot,
    required this.preview,
    required this.onPreviewChanged,
  });

  final _KnowledgeSourceContentSnapshot snapshot;
  final bool preview;
  final ValueChanged<bool> onPreviewChanged;

  @override
  Widget build(BuildContext context) {
    final source = snapshot.source!;
    final isZh = openHandIsChineseLocale(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final previewAvailable = _supportsMarkdownPreview(source, snapshot);
    final showPreview = previewAvailable && preview;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KnowledgeDialogSection(
          title: source.title,
          subtitle: snapshot.path.isEmpty ? source.originalPath : snapshot.path,
          icon: _iconForKind(source.kind),
          margin: const EdgeInsets.only(bottom: 10),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              KnowledgeDialogChip(
                icon: Icons.category_outlined,
                label: _localizedKind(source.kind, context),
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
                    ? (isZh ? '原文' : 'Original')
                    : (isZh ? '索引内容' : 'Indexed content'),
              ),
              KnowledgeDialogChip(
                icon: Icons.schedule_rounded,
                label: formatYearMonthDayHm(source.updatedAt.toLocal()),
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
          const SizedBox(height: 10),
        ],
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.44),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.72),
            ),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (previewAvailable)
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment<bool>(
                      value: true,
                      icon: const Icon(Icons.visibility_outlined, size: 16),
                      label: Text(isZh ? '预览' : 'Preview'),
                    ),
                    ButtonSegment<bool>(
                      value: false,
                      icon: const Icon(Icons.code_rounded, size: 16),
                      label: Text(isZh ? '源码' : 'Source'),
                    ),
                  ],
                  selected: {preview},
                  onSelectionChanged: (values) =>
                      onPreviewChanged(values.first),
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
              FilledButton.tonalIcon(
                onPressed: snapshot.text.trim().isEmpty
                    ? null
                    : () {
                        Clipboard.setData(ClipboardData(text: snapshot.text));
                        OpenHandSnackBar.showSuccess(
                          context,
                          isZh ? '内容已复制。' : 'Content copied.',
                        );
                      },
                icon: const Icon(Icons.copy_all_rounded),
                label: Text(isZh ? '复制内容' : 'Copy Content'),
                style: FilledButton.styleFrom(
                  visualDensity: const VisualDensity(
                    horizontal: -1,
                    vertical: -1,
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              Text(
                isZh
                    ? '${snapshot.lineCount} 行 · ${formatByteSize(snapshot.loadedBytes)}'
                    : '${snapshot.lineCount} lines · ${formatByteSize(snapshot.loadedBytes)}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: showPreview
                ? _KnowledgeMarkdownViewer(
                    key: const ValueKey<String>('markdown-preview'),
                    text: snapshot.text,
                  )
                : _KnowledgeSourceTextViewer(
                    key: const ValueKey<String>('source-view'),
                    text: snapshot.text,
                    emptyText: isZh ? '暂无可浏览内容。' : 'No content to view.',
                  ),
          ),
        ),
      ],
    );
  }
}

class _KnowledgeMarkdownViewer extends StatelessWidget {
  const _KnowledgeMarkdownViewer({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.46),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.72),
        ),
      ),
      child: Markdown(
        data: text.trim(),
        selectable: true,
        softLineBreak: true,
        extensionSet: md.ExtensionSet.gitHubFlavored,
        padding: const EdgeInsets.all(14),
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
      ),
    );
  }
}

class _KnowledgeSourceTextViewer extends StatelessWidget {
  const _KnowledgeSourceTextViewer({
    super.key,
    required this.text,
    required this.emptyText,
  });

  final String text;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final value = text.trim().isEmpty ? emptyText : _withLineNumbers(text);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.46),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.72),
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SelectableText(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
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
      notice = null,
      loadedFromFile = false,
      loadedBytes = 0,
      lineCount = 0;

  const _KnowledgeSourceContentSnapshot({
    required this.source,
    required this.text,
    required this.path,
    required this.notice,
    required this.loadedFromFile,
    required this.loadedBytes,
    required this.lineCount,
  });

  final KnowledgeSource? source;
  final String text;
  final String path;
  final _KnowledgeSourceContentNotice? notice;
  final bool loadedFromFile;
  final int loadedBytes;
  final int lineCount;

  static Future<_KnowledgeSourceContentSnapshot> fromSource({
    required KnowledgeSource source,
    required List<KnowledgeChunk> chunks,
  }) async {
    final preferredFile = await _resolveReadableFile(source);
    if (preferredFile != null && _shouldReadFile(source)) {
      try {
        final stat = await preferredFile.stat();
        final truncated = stat.size > _kMaxFilePreviewBytes;
        final bytes = await _readPreviewBytes(preferredFile, stat.size);
        final text = utf8.decode(bytes, allowMalformed: true);
        return _KnowledgeSourceContentSnapshot(
          source: source,
          text: text,
          path: preferredFile.path,
          loadedFromFile: true,
          loadedBytes: bytes.length,
          lineCount: _lineCount(text),
          notice: truncated
              ? _KnowledgeSourceContentNotice.largeFileTruncated
              : null,
        );
      } catch (_) {
        // Fall through to indexed chunks.
      }
    }

    final text = _chunksToText(chunks);
    return _KnowledgeSourceContentSnapshot(
      source: source,
      text: text,
      path: preferredFile?.path ?? source.originalPath,
      loadedFromFile: false,
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
  final candidates = <String>[
    source.storedPath,
    source.originalPath,
  ].map((path) => path.trim()).where((path) => path.isNotEmpty).toSet();
  for (final path in candidates) {
    final file = File(path);
    if (await file.exists()) return file;
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
  final extension = p
      .extension(source.originalPath)
      .replaceFirst('.', '')
      .trim()
      .toLowerCase();
  return const <String>{
    'md',
    'markdown',
    'txt',
    'text',
    'log',
    'html',
    'htm',
    'csv',
    'json',
    'toml',
    'yaml',
    'yml',
    'dart',
    'js',
    'jsx',
    'ts',
    'tsx',
    'py',
    'java',
    'kt',
    'kts',
    'swift',
    'go',
    'rs',
    'c',
    'cc',
    'cpp',
    'h',
    'hpp',
    'cs',
    'php',
    'rb',
    'sh',
    'bash',
    'zsh',
    'fish',
    'sql',
    'xml',
    'css',
    'scss',
    'less',
  }.contains(extension);
}

Future<Uint8List> _readPreviewBytes(File file, int fileSize) async {
  final end = math.min(fileSize, _kMaxFilePreviewBytes);
  final builder = await file.openRead(0, end).fold<BytesBuilder>(
    BytesBuilder(copy: false),
    (builder, chunk) {
      builder.add(chunk);
      return builder;
    },
  );
  return builder.takeBytes();
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
  final isZh = openHandIsChineseLocale(context);
  return switch (notice) {
    _KnowledgeSourceContentNotice.largeFileTruncated =>
      isZh
          ? '文件较大，当前仅预览前 ${formatByteSize(_kMaxFilePreviewBytes)}。'
          : 'The file is large. Showing only the first ${formatByteSize(_kMaxFilePreviewBytes)}.',
    _KnowledgeSourceContentNotice.indexedFallback =>
      isZh
          ? '当前展示已索引的分块内容；原文件不可直接作为文本浏览。'
          : 'Showing indexed chunks because the original file cannot be viewed directly as text.',
    _KnowledgeSourceContentNotice.empty =>
      isZh
          ? '没有可浏览的原文或索引内容。'
          : 'No original or indexed content is available to view.',
  };
}

int _lineCount(String text) {
  if (text.isEmpty) return 0;
  return '\n'.allMatches(text).length + 1;
}

IconData _iconForKind(String kind) {
  return switch (kind) {
    'markdown' => Icons.notes_rounded,
    'code' => Icons.code_rounded,
    'pdf' => Icons.picture_as_pdf_outlined,
    'html' => Icons.language_rounded,
    'docx' => Icons.article_outlined,
    'spreadsheet' => Icons.table_chart_outlined,
    'presentation' => Icons.slideshow_outlined,
    'table' => Icons.dataset_outlined,
    'structured' => Icons.data_object_rounded,
    _ => Icons.description_outlined,
  };
}

String _localizedKind(String kind, BuildContext context) {
  final isZh = openHandIsChineseLocale(context);
  return switch (kind) {
    'markdown' => isZh ? 'Markdown 文档' : 'Markdown',
    'text' => isZh ? '文本' : 'Text',
    'code' => isZh ? '代码' : 'Code',
    'pdf' => isZh ? 'PDF' : 'PDF',
    'html' => isZh ? '网页 HTML' : 'HTML',
    'docx' => isZh ? 'Word 文档' : 'Word document',
    'spreadsheet' => isZh ? '电子表格' : 'Spreadsheet',
    'presentation' => isZh ? '演示文稿' : 'Presentation',
    'table' => isZh ? '表格数据' : 'Table data',
    'structured' => isZh ? '结构化数据' : 'Structured data',
    'note' => isZh ? '笔记' : 'Note',
    _ => kind.trim().isEmpty ? '-' : kind,
  };
}

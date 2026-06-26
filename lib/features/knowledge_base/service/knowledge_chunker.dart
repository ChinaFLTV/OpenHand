import '../../../shared/util/stable_hash.dart';
import '../model/knowledge_base_settings.dart';
import '../model/knowledge_chunk.dart';
import '../model/knowledge_source.dart';

class KnowledgeChunker {
  const KnowledgeChunker();

  List<KnowledgeChunk> chunk({
    required KnowledgeSource source,
    required String text,
    required KnowledgeBaseSettings settings,
    List<String> tags = const <String>[],
  }) {
    final normalized = text.replaceAll('\r\n', '\n').trim();
    if (normalized.isEmpty) return const <KnowledgeChunk>[];
    final sections = _markdownSections(normalized);
    final chunks = <KnowledgeChunk>[];
    for (final section in sections) {
      final windows = _window(section.content, settings);
      for (final window in windows) {
        final index = chunks.length;
        final content = window.text.trim();
        if (content.isEmpty) continue;
        chunks.add(
          KnowledgeChunk(
            id: '${source.id}_chunk_$index',
            sourceId: source.id,
            chunkIndex: index,
            parentChunkId: section.headingPath.isEmpty
                ? null
                : '${source.id}_parent_${stableFnv1a32Hex(section.headingPath)}',
            title: section.title.isEmpty ? source.title : section.title,
            headingPath: section.headingPath,
            content: content,
            contentHash: stableFnv1a32Hex(content),
            charCount: content.length,
            tokenEstimate: _estimateTokens(content),
            startOffset: window.start,
            endOffset: window.end,
            documentTime: source.documentTime,
            createdAt: DateTime.now().toUtc(),
            updatedAt: DateTime.now().toUtc(),
            metadata: <String, Object?>{
              'strategy': settings.chunkStrategy,
              'source_path': source.originalPath,
              'imported_at': source.importedAt.toUtc().toIso8601String(),
            },
            tags: tags,
          ),
        );
      }
    }
    return chunks;
  }

  List<_Section> _markdownSections(String text) {
    final lines = text.split('\n');
    final sections = <_Section>[];
    final headingStack = <String>[];
    final buffer = StringBuffer();
    var sectionStart = 0;

    void flush() {
      final content = buffer.toString().trim();
      if (content.isEmpty) return;
      final headingPath = headingStack.join(' > ');
      sections.add(
        _Section(
          title: headingStack.isEmpty ? '' : headingStack.last,
          headingPath: headingPath,
          content: content,
          start: sectionStart,
        ),
      );
      buffer.clear();
    }

    var offset = 0;
    for (final line in lines) {
      final heading = RegExp(r'^(#{1,6})\s+(.+)$').firstMatch(line);
      if (heading != null) {
        flush();
        final level = heading.group(1)!.length;
        while (headingStack.length >= level) {
          headingStack.removeLast();
        }
        headingStack.add(heading.group(2)!.trim());
        sectionStart = offset;
      }
      buffer.writeln(line);
      offset += line.length + 1;
    }
    flush();
    if (sections.isEmpty) {
      return <_Section>[
        _Section(title: '', headingPath: '', content: text, start: 0),
      ];
    }
    return sections;
  }

  List<_Window> _window(String text, KnowledgeBaseSettings settings) {
    final hardMaxChars = settings.hardMaxTokens * 4;
    final targetChars = settings.targetTokens * 4;
    final overlapChars = settings.overlapTokens * 4;
    if (text.length <= hardMaxChars) {
      return <_Window>[_Window(text: text, start: 0, end: text.length)];
    }
    final paragraphs = text.split(RegExp(r'\n{2,}'));
    final windows = <_Window>[];
    final buffer = StringBuffer();
    var start = 0;
    var cursor = 0;
    for (final paragraph in paragraphs) {
      final addition = paragraph.trim();
      if (addition.isEmpty) {
        cursor += paragraph.length + 2;
        continue;
      }
      if (buffer.length + addition.length > targetChars && buffer.isNotEmpty) {
        final chunkText = buffer.toString().trim();
        windows.add(_Window(text: chunkText, start: start, end: cursor));
        final overlap = chunkText.length <= overlapChars
            ? chunkText
            : chunkText.substring(chunkText.length - overlapChars);
        buffer
          ..clear()
          ..writeln(overlap)
          ..writeln();
        start = (cursor - overlap.length).clamp(0, text.length);
      }
      buffer
        ..writeln(addition)
        ..writeln();
      cursor += paragraph.length + 2;
    }
    final tail = buffer.toString().trim();
    if (tail.isNotEmpty) {
      windows.add(_Window(text: tail, start: start, end: text.length));
    }
    return windows;
  }

  int _estimateTokens(String text) => (text.length / 4).ceil();
}

class _Section {
  const _Section({
    required this.title,
    required this.headingPath,
    required this.content,
    required this.start,
  });

  final String title;
  final String headingPath;
  final String content;
  final int start;
}

class _Window {
  const _Window({required this.text, required this.start, required this.end});

  final String text;
  final int start;
  final int end;
}

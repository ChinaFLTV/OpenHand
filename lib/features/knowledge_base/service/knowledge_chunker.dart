import 'dart:convert';

import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/stable_hash.dart';
import '../../../shared/util/text_clip.dart';
import '../model/knowledge_base_settings.dart';
import '../model/knowledge_chunk.dart';
import '../model/knowledge_source.dart';

final RegExp _markdownHeadingPattern = RegExp(r'^(#{1,6})\s+(.+)$');

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
    final strategy = KnowledgeChunkStrategy.normalize(settings.chunkStrategy);
    final sections = strategy == KnowledgeChunkStrategy.markdownHeadingRecursive
        ? _markdownSections(
            normalized,
            maxSections: kKnowledgeMaxChunkCountPerSource,
          )
        : <_Section>[
            _Section(title: '', headingPath: '', content: normalized, start: 0),
          ];
    final chunks = <KnowledgeChunk>[];
    final now = DateTime.now().toUtc();
    for (final section in sections) {
      final remaining = kKnowledgeMaxChunkCountPerSource - chunks.length;
      if (remaining <= 0) {
        throw StateError('知识源分块数量超过安全上限。');
      }
      final windows = switch (strategy) {
        KnowledgeChunkStrategy.fixedTokenWindow => _fixedWindows(
          section.content,
          settings,
          maxWindows: remaining,
        ),
        KnowledgeChunkStrategy.semanticLight => _semanticWindows(
          section.content,
          settings,
          maxWindows: remaining,
        ),
        _ => _paragraphWindows(
          section.content,
          settings,
          maxWindows: remaining,
        ),
      };
      for (final window in windows) {
        final index = chunks.length;
        final content = window.text.trim();
        if (content.isEmpty) continue;
        final startOffset = _clampInt(
          section.start + window.start,
          0,
          normalized.length,
        );
        final endOffset = _clampInt(
          section.start + window.end,
          startOffset,
          normalized.length,
        );
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
            startOffset: startOffset,
            endOffset: endOffset,
            documentTime: source.documentTime,
            createdAt: now,
            updatedAt: now,
            metadata: <String, Object?>{
              'strategy': strategy,
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

  List<_Section> _markdownSections(String text, {required int maxSections}) {
    final sections = <_Section>[];
    final headingStack = <String>[];
    final buffer = StringBuffer();
    var sectionStart = 0;

    void flush() {
      final content = buffer.toString().trim();
      if (content.isEmpty) return;
      if (sections.length >= maxSections) {
        throw StateError('知识源章节数量超过安全上限。');
      }
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
    for (final line in LineSplitter.split(text)) {
      final heading = _markdownHeadingPattern.firstMatch(line);
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

  List<_Window> _paragraphWindows(
    String text,
    KnowledgeBaseSettings settings, {
    required int maxWindows,
  }) {
    final tuning = _tuning(settings);
    if (text.length <= tuning.hardMaxChars) {
      if (maxWindows <= 0) {
        throw StateError('知识源分块数量超过安全上限。');
      }
      return <_Window>[_Window(text: text, start: 0, end: text.length)];
    }
    return _windowsFromUnits(
      _paragraphUnits(text),
      settings,
      maxWindows: maxWindows,
    );
  }

  List<_Window> _fixedWindows(
    String text,
    KnowledgeBaseSettings settings, {
    required int maxWindows,
  }) {
    final tuning = _tuning(settings);
    final windowChars = _clampInt(tuning.targetChars, 1, tuning.hardMaxChars);
    final overlapChars = _clampInt(tuning.overlapChars, 0, windowChars - 1);
    final windows = <_Window>[];
    var start = 0;
    while (start < text.length) {
      if (windows.length >= maxWindows) {
        throw StateError('知识源分块数量超过安全上限。');
      }
      final end = _clampInt(start + windowChars, start + 1, text.length);
      windows.add(
        _Window(text: text.substring(start, end), start: start, end: end),
      );
      if (end >= text.length) break;
      start = _clampInt(end - overlapChars, start + 1, text.length);
    }
    return windows;
  }

  List<_Window> _semanticWindows(
    String text,
    KnowledgeBaseSettings settings, {
    required int maxWindows,
  }) {
    final tuning = _tuning(settings);
    if (text.length <= tuning.hardMaxChars) {
      if (maxWindows <= 0) {
        throw StateError('知识源分块数量超过安全上限。');
      }
      return <_Window>[_Window(text: text, start: 0, end: text.length)];
    }
    return _windowsFromUnits(
      _sentenceUnits(text),
      settings,
      maxWindows: maxWindows,
    );
  }

  List<_Window> _windowsFromUnits(
    Iterable<_Window> units,
    KnowledgeBaseSettings settings, {
    required int maxWindows,
  }) {
    final iterator = units.iterator;
    if (!iterator.moveNext()) return const <_Window>[];
    final tuning = _tuning(settings);
    final windows = <_Window>[];
    final buffer = StringBuffer();
    var start = iterator.current.start;
    var end = start;

    void addWindow(_Window window) {
      if (windows.length >= maxWindows) {
        throw StateError('知识源分块数量超过安全上限。');
      }
      windows.add(window);
    }

    do {
      final unit = iterator.current;
      if (unit.text.length > tuning.hardMaxChars) {
        if (buffer.isNotEmpty) {
          final chunkText = buffer.toString().trim();
          addWindow(_Window(text: chunkText, start: start, end: end));
          buffer.clear();
        }
        for (final window in _fixedWindows(
          unit.text,
          settings,
          maxWindows: maxWindows - windows.length,
        )) {
          addWindow(
            _Window(
              text: window.text,
              start: unit.start + window.start,
              end: unit.start + window.end,
            ),
          );
        }
        start = unit.end;
        end = unit.end;
        continue;
      }
      if (buffer.isEmpty) start = unit.start;
      final separator = buffer.isEmpty ? 0 : 2;
      if (buffer.length + separator + unit.text.length > tuning.targetChars &&
          buffer.isNotEmpty) {
        final chunkText = buffer.toString().trim();
        addWindow(_Window(text: chunkText, start: start, end: end));
        final overlap = _tailOverlap(chunkText, tuning.overlapChars);
        buffer.clear();
        if (overlap.isEmpty) {
          start = unit.start;
        } else {
          buffer
            ..writeln(overlap)
            ..writeln();
          start = _clampInt(end - overlap.length, 0, end);
        }
      }
      buffer
        ..writeln(unit.text)
        ..writeln();
      end = unit.end;
    } while (iterator.moveNext());
    final tail = buffer.toString().trim();
    if (tail.isNotEmpty) {
      addWindow(_Window(text: tail, start: start, end: end));
    }
    return windows;
  }

  Iterable<_Window> _paragraphUnits(String text) sync* {
    var start = 0;
    for (final separator in RegExp(r'\n{2,}').allMatches(text)) {
      final unit = _trimmedUnit(text, start, separator.start);
      if (unit != null) yield unit;
      start = separator.end;
    }
    final tail = _trimmedUnit(text, start, text.length);
    if (tail != null) yield tail;
  }

  Iterable<_Window> _sentenceUnits(String text) sync* {
    for (final paragraph in _paragraphUnits(text)) {
      var start = paragraph.start;
      for (var i = paragraph.start; i < paragraph.end; i++) {
        if (!_isSentenceBreakChar(text[i])) continue;
        final end = i + 1;
        final unit = _trimmedUnit(text, start, end);
        if (unit != null) yield unit;
        start = end;
      }
      final tail = _trimmedUnit(text, start, paragraph.end);
      if (tail != null) yield tail;
    }
  }

  _Window? _trimmedUnit(String text, int start, int end) {
    if (end <= start) return null;
    var trimmedStart = start;
    var trimmedEnd = end;
    while (trimmedStart < trimmedEnd && text[trimmedStart].trim().isEmpty) {
      trimmedStart += 1;
    }
    while (trimmedEnd > trimmedStart && text[trimmedEnd - 1].trim().isEmpty) {
      trimmedEnd -= 1;
    }
    if (trimmedEnd <= trimmedStart) return null;
    return _Window(
      text: text.substring(trimmedStart, trimmedEnd),
      start: trimmedStart,
      end: trimmedEnd,
    );
  }

  bool _isSentenceBreakChar(String value) {
    return value == '.' ||
        value == '!' ||
        value == '?' ||
        value == ';' ||
        value == '。' ||
        value == '！' ||
        value == '？' ||
        value == '；';
  }

  String _tailOverlap(String text, int maxChars) {
    if (maxChars <= 0 || text.isEmpty) return '';
    if (text.length <= maxChars) return text;
    return text.substring(safeUtf16SuffixStart(text, text.length - maxChars));
  }

  _ChunkTuning _tuning(KnowledgeBaseSettings settings) {
    final targetChars =
        _clampInt(
          settings.targetTokens <= 0 ? 1 : settings.targetTokens,
          1,
          1000000,
        ) *
        4;
    final hardMaxChars =
        _clampInt(
          settings.hardMaxTokens <= 0
              ? settings.targetTokens
              : settings.hardMaxTokens,
          1,
          1000000,
        ) *
        4;
    final effectiveHardMax = hardMaxChars < targetChars
        ? targetChars
        : hardMaxChars;
    final overlapChars =
        _clampInt(
          settings.overlapTokens <= 0 ? 0 : settings.overlapTokens,
          0,
          1000000,
        ) *
        4;
    return _ChunkTuning(
      targetChars: targetChars,
      hardMaxChars: effectiveHardMax,
      overlapChars: _clampInt(overlapChars, 0, targetChars - 1),
    );
  }

  int _estimateTokens(String text) => (text.length / 4).ceil();

  int _clampInt(int value, int lowerLimit, int upperLimit) {
    return clampIntToRange(value, min: lowerLimit, max: upperLimit);
  }
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

class _ChunkTuning {
  const _ChunkTuning({
    required this.targetChars,
    required this.hardMaxChars,
    required this.overlapChars,
  });

  final int targetChars;
  final int hardMaxChars;
  final int overlapChars;
}

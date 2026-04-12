import 'dart:math' as math;

import 'package:flutter/services.dart';

import '../../app/model/editor_indent.dart';

class EditorIndentationEdit {
  const EditorIndentationEdit({
    required this.text,
    required this.selection,
    required this.didChange,
  });

  final String text;
  final TextSelection selection;
  final bool didChange;
}

class EditorCommentStyle {
  const EditorCommentStyle({
    this.linePrefix,
    this.blockCommentStart,
    this.blockCommentEnd,
  });

  final String? linePrefix;
  final String? blockCommentStart;
  final String? blockCommentEnd;

  bool get usesLineComment => linePrefix?.trim().isNotEmpty == true;

  bool get usesBlockComment =>
      blockCommentStart?.trim().isNotEmpty == true &&
      blockCommentEnd?.trim().isNotEmpty == true;
}

class _EditorBlockCommentTarget {
  const _EditorBlockCommentTarget({
    required this.start,
    required this.end,
    required this.wasCollapsed,
  });

  final int start;
  final int end;
  final bool wasCollapsed;
}

EditorIndentationEdit applyEditorIndentation({
  required String text,
  required TextSelection selection,
  required int indentSpaces,
  bool outdent = false,
}) {
  if (!selection.isValid) {
    return EditorIndentationEdit(
      text: text,
      selection: selection,
      didChange: false,
    );
  }

  final normalizedIndentSpaces = normalizeEditorIndentSpaces(indentSpaces);
  final baseOffset = selection.baseOffset.clamp(0, text.length);
  final extentOffset = selection.extentOffset.clamp(0, text.length);
  final normalizedSelection = selection.copyWith(
    baseOffset: baseOffset,
    extentOffset: extentOffset,
  );
  final startOffset = math.min(baseOffset, extentOffset);
  final endOffset = math.max(baseOffset, extentOffset);

  if (!outdent && !_selectionSpansMultipleLines(text, startOffset, endOffset)) {
    if (normalizedSelection.isCollapsed) {
      final spacesToInsert = _spacesForNextTabStop(
        text,
        startOffset,
        normalizedIndentSpaces,
      );
      final replacement = _spaces(spacesToInsert);
      final nextText = text.replaceRange(startOffset, endOffset, replacement);
      return EditorIndentationEdit(
        text: nextText,
        selection: TextSelection.collapsed(
          offset: startOffset + replacement.length,
        ),
        didChange: nextText != text,
      );
    }

    final replacement = _spaces(normalizedIndentSpaces);
    final nextText = text.replaceRange(startOffset, endOffset, replacement);
    return EditorIndentationEdit(
      text: nextText,
      selection: TextSelection.collapsed(
        offset: startOffset + replacement.length,
      ),
      didChange: nextText != text,
    );
  }

  return _applyLineIndentation(
    text: text,
    selection: normalizedSelection,
    indentSpaces: normalizedIndentSpaces,
    outdent: outdent,
  );
}

EditorIndentationEdit applyEditorAutoIndentNewline({
  required String text,
  required TextSelection selection,
  required int indentSpaces,
  String? language,
}) {
  if (!selection.isValid) {
    return EditorIndentationEdit(
      text: text,
      selection: selection,
      didChange: false,
    );
  }

  final normalizedIndentSpaces = normalizeEditorIndentSpaces(indentSpaces);
  final baseOffset = selection.baseOffset.clamp(0, text.length);
  final extentOffset = selection.extentOffset.clamp(0, text.length);
  final startOffset = math.min(baseOffset, extentOffset);
  final endOffset = math.max(baseOffset, extentOffset);
  final lineStart = _lineStartOffset(text, startOffset);
  final lineEnd = _lineEndOffset(text, startOffset);
  final lineText = text.substring(lineStart, lineEnd);
  final indentation = _leadingIndentation(lineText);
  final beforeCursor = text.substring(lineStart, startOffset);
  final afterCursor = text.substring(endOffset, lineEnd);
    final normalizedLanguage = (language ?? '').trim().toLowerCase();
  final openingDelimiter = _trailingOpeningDelimiter(beforeCursor);
    final shouldIndentExtra =
      openingDelimiter != null ||
      _shouldIncreaseIndentForLanguage(normalizedLanguage, beforeCursor);
  final expectedClosingDelimiter = openingDelimiter == null
      ? null
      : _matchingClosingDelimiter(openingDelimiter);
  final shouldSplitPair =
      expectedClosingDelimiter != null &&
      _leadingNonWhitespaceCharacter(afterCursor) == expectedClosingDelimiter;
  final extraIndent = shouldIndentExtra ? _spaces(normalizedIndentSpaces) : '';
  final replacement = shouldSplitPair
      ? '\n$indentation$extraIndent\n$indentation'
      : '\n$indentation$extraIndent';
  final nextText = text.replaceRange(startOffset, endOffset, replacement);
  final caretOffset = startOffset + 1 + indentation.length + extraIndent.length;
  return EditorIndentationEdit(
    text: nextText,
    selection: TextSelection.collapsed(offset: caretOffset),
    didChange: nextText != text,
  );
}

EditorIndentationEdit applyEditorToggleComment({
  required String text,
  required TextSelection selection,
  required EditorCommentStyle commentStyle,
}) {
  if (commentStyle.usesLineComment) {
    return applyEditorToggleLineComment(
      text: text,
      selection: selection,
      commentPrefix: commentStyle.linePrefix!,
    );
  }
  if (commentStyle.usesBlockComment) {
    return _applyEditorToggleBlockComment(
      text: text,
      selection: selection,
      blockCommentStart: commentStyle.blockCommentStart!,
      blockCommentEnd: commentStyle.blockCommentEnd!,
    );
  }
  return EditorIndentationEdit(
    text: text,
    selection: selection,
    didChange: false,
  );
}

EditorIndentationEdit applyEditorToggleLineComment({
  required String text,
  required TextSelection selection,
  required String commentPrefix,
}) {
  if (!selection.isValid || commentPrefix.trim().isEmpty) {
    return EditorIndentationEdit(
      text: text,
      selection: selection,
      didChange: false,
    );
  }

  final baseOffset = selection.baseOffset.clamp(0, text.length);
  final extentOffset = selection.extentOffset.clamp(0, text.length);
  final normalizedSelection = selection.copyWith(
    baseOffset: baseOffset,
    extentOffset: extentOffset,
  );
  final startOffset = math.min(baseOffset, extentOffset);
  final endOffset = math.max(baseOffset, extentOffset);
  final blockStart = _lineStartOffset(text, startOffset);
  final effectiveEndOffset = _effectiveBlockEndOffset(
    text,
    startOffset,
    endOffset,
    normalizedSelection.isCollapsed,
  );
  final blockEnd = _lineEndOffset(text, effectiveEndOffset);

  var hasNonEmptyLine = false;
  var everyNonEmptyLineCommented = true;
  var scanLineStart = blockStart;
  while (true) {
    final lineEnd = _lineEndOffset(text, scanLineStart);
    final lineText = text.substring(scanLineStart, lineEnd);
    final indentationEnd = _leadingIndentEnd(lineText);
    final isNonEmpty = lineText.trim().isNotEmpty;
    if (isNonEmpty) {
      hasNonEmptyLine = true;
      if (!_lineHasCommentPrefix(lineText, indentationEnd, commentPrefix)) {
        everyNonEmptyLineCommented = false;
      }
    }
    if (lineEnd >= blockEnd || lineEnd >= text.length) {
      break;
    }
    scanLineStart = lineEnd + 1;
  }

  final shouldUncomment = hasNonEmptyLine && everyNonEmptyLineCommented;
  final commentEmptyLines = !hasNonEmptyLine;

  var nextBaseOffset = baseOffset;
  var nextExtentOffset = extentOffset;
  var changed = false;
  final buffer = StringBuffer()..write(text.substring(0, blockStart));
  var lineStart = blockStart;
  while (true) {
    final lineEnd = _lineEndOffset(text, lineStart);
    final hasNewline = lineEnd < text.length && text.codeUnitAt(lineEnd) == 10;
    final lineText = text.substring(lineStart, lineEnd);
    final indentationEnd = _leadingIndentEnd(lineText);
    final lineInsertionOffset = lineStart + indentationEnd;
    final isNonEmpty = lineText.trim().isNotEmpty;
    final shouldProcessLine = isNonEmpty || commentEmptyLines;

    if (!shouldProcessLine) {
      buffer.write(lineText);
    } else if (shouldUncomment) {
      if (_lineHasCommentPrefix(lineText, indentationEnd, commentPrefix)) {
        var removedLength = commentPrefix.length;
        final removalEnd = indentationEnd + removedLength;
        if (lineText.length > removalEnd && lineText.codeUnitAt(removalEnd) == 32) {
          removedLength += 1;
        }
        buffer.write(lineText.substring(0, indentationEnd));
        buffer.write(lineText.substring(indentationEnd + removedLength));
        if (removedLength > 0) {
          changed = true;
        }
        if (baseOffset > lineInsertionOffset) {
          nextBaseOffset -= math.min(
            removedLength,
            baseOffset - lineInsertionOffset,
          );
        }
        if (extentOffset > lineInsertionOffset) {
          nextExtentOffset -= math.min(
            removedLength,
            extentOffset - lineInsertionOffset,
          );
        }
      } else {
        buffer.write(lineText);
      }
    } else {
      final prefixText = isNonEmpty ? '$commentPrefix ' : commentPrefix;
      buffer.write(lineText.substring(0, indentationEnd));
      buffer.write(prefixText);
      buffer.write(lineText.substring(indentationEnd));
      changed = true;
      if (baseOffset >= lineInsertionOffset) {
        nextBaseOffset += prefixText.length;
      }
      if (extentOffset >= lineInsertionOffset) {
        nextExtentOffset += prefixText.length;
      }
    }

    if (!hasNewline || lineEnd >= blockEnd) {
      break;
    }
    buffer.write('\n');
    lineStart = lineEnd + 1;
  }
  buffer.write(text.substring(blockEnd));

  final nextText = buffer.toString();
  if (!changed) {
    return EditorIndentationEdit(
      text: text,
      selection: normalizedSelection,
      didChange: false,
    );
  }
  return EditorIndentationEdit(
    text: nextText,
    selection: normalizedSelection.copyWith(
      baseOffset: nextBaseOffset.clamp(0, nextText.length),
      extentOffset: nextExtentOffset.clamp(0, nextText.length),
    ),
    didChange: true,
  );
}

EditorIndentationEdit _applyEditorToggleBlockComment({
  required String text,
  required TextSelection selection,
  required String blockCommentStart,
  required String blockCommentEnd,
}) {
  if (!selection.isValid ||
      blockCommentStart.trim().isEmpty ||
      blockCommentEnd.trim().isEmpty) {
    return EditorIndentationEdit(
      text: text,
      selection: selection,
      didChange: false,
    );
  }

  final baseOffset = selection.baseOffset.clamp(0, text.length);
  final extentOffset = selection.extentOffset.clamp(0, text.length);
  final normalizedSelection = selection.copyWith(
    baseOffset: baseOffset,
    extentOffset: extentOffset,
  );
  final target = _blockCommentTargetForSelection(text, normalizedSelection);
  if (target.end <= target.start) {
    return EditorIndentationEdit(
      text: text,
      selection: normalizedSelection,
      didChange: false,
    );
  }

  final targetText = text.substring(target.start, target.end);
  if (targetText.isEmpty) {
    return EditorIndentationEdit(
      text: text,
      selection: normalizedSelection,
      didChange: false,
    );
  }

  final unwrapped = _unwrapBlockComment(
    targetText,
    blockCommentStart: blockCommentStart,
    blockCommentEnd: blockCommentEnd,
  );
  final replacement = unwrapped ??
      (targetText.contains('\n')
          ? '$blockCommentStart\n$targetText\n$blockCommentEnd'
          : '$blockCommentStart $targetText $blockCommentEnd');
  final nextText = text.replaceRange(target.start, target.end, replacement);
  if (nextText == text) {
    return EditorIndentationEdit(
      text: text,
      selection: normalizedSelection,
      didChange: false,
    );
  }

  final nextSelection = target.wasCollapsed
      ? TextSelection.collapsed(offset: target.start + replacement.length)
      : _selectionForEditedRange(
          normalizedSelection,
          target.start,
          target.start + replacement.length,
        );
  return EditorIndentationEdit(
    text: nextText,
    selection: nextSelection,
    didChange: true,
  );
}

EditorCommentStyle? editorCommentStyleForLanguage(String language) {
  final normalized = language.trim().toLowerCase();
  return switch (normalized) {
    'dart' ||
    'javascript' ||
    'typescript' ||
    'go' ||
    'rust' ||
    'java' ||
    'kotlin' ||
    'c' ||
    'cpp' ||
    'swift' ||
    'csharp' ||
    'fsharp' ||
    'php' ||
    'scala' ||
    'zig' ||
    'gleam' ||
    'prisma' ||
    'typst' => const EditorCommentStyle(linePrefix: '//'),
    'python' ||
    'shell' ||
    'terraform' ||
    'yaml' ||
    'toml' ||
    'ruby' ||
    'perl' ||
    'r' ||
    'julia' ||
    'elixir' ||
    'graphql' ||
    'dockerfile' => const EditorCommentStyle(linePrefix: '#'),
    'lua' || 'sql' || 'haskell' =>
      const EditorCommentStyle(linePrefix: '--'),
    'erlang' => const EditorCommentStyle(linePrefix: '%'),
    'clojure' => const EditorCommentStyle(linePrefix: ';'),
    'html' || 'markdown' => const EditorCommentStyle(
      blockCommentStart: '<!--',
      blockCommentEnd: '-->',
    ),
    'css' => const EditorCommentStyle(
      blockCommentStart: '/*',
      blockCommentEnd: '*/',
    ),
    'vue' || 'svelte' || 'astro' => const EditorCommentStyle(
      blockCommentStart: '<!--',
      blockCommentEnd: '-->',
    ),
    _ => null,
  };
}

String? editorLineCommentPrefixForLanguage(String language) {
  return editorCommentStyleForLanguage(language)?.linePrefix;
}

EditorIndentationEdit _applyLineIndentation({
  required String text,
  required TextSelection selection,
  required int indentSpaces,
  required bool outdent,
}) {
  final baseOffset = selection.baseOffset;
  final extentOffset = selection.extentOffset;
  final startOffset = math.min(baseOffset, extentOffset);
  final endOffset = math.max(baseOffset, extentOffset);
  final blockStart = _lineStartOffset(text, startOffset);
  final effectiveEndOffset = _effectiveBlockEndOffset(
    text,
    startOffset,
    endOffset,
    selection.isCollapsed,
  );
  final blockEnd = _lineEndOffset(text, effectiveEndOffset);
  final indentText = _spaces(indentSpaces);

  var nextBaseOffset = baseOffset;
  var nextExtentOffset = extentOffset;
  var changed = false;

  final buffer = StringBuffer()..write(text.substring(0, blockStart));
  var lineStart = blockStart;
  while (lineStart < blockEnd) {
    final nextNewline = text.indexOf('\n', lineStart);
    final hasNewline = nextNewline != -1 && nextNewline < blockEnd;
    final lineEnd = hasNewline ? nextNewline : blockEnd;
    final lineText = text.substring(lineStart, lineEnd);

    if (outdent) {
      final removedSpaces = _removableIndentWidth(lineText, indentSpaces);
      buffer.write(lineText.substring(removedSpaces));
      if (removedSpaces > 0) {
        changed = true;
      }
      if (baseOffset > lineStart) {
        nextBaseOffset -= math.min(removedSpaces, baseOffset - lineStart);
      }
      if (extentOffset > lineStart) {
        nextExtentOffset -= math.min(removedSpaces, extentOffset - lineStart);
      }
    } else {
      buffer.write(indentText);
      buffer.write(lineText);
      changed = true;
      if (baseOffset >= lineStart) {
        nextBaseOffset += indentSpaces;
      }
      if (extentOffset >= lineStart) {
        nextExtentOffset += indentSpaces;
      }
    }

    if (!hasNewline) {
      break;
    }
    buffer.write('\n');
    lineStart = nextNewline + 1;
  }
  buffer.write(text.substring(blockEnd));

  final nextText = buffer.toString();
  if (!changed) {
    return EditorIndentationEdit(
      text: text,
      selection: selection,
      didChange: false,
    );
  }
  return EditorIndentationEdit(
    text: nextText,
    selection: selection.copyWith(
      baseOffset: nextBaseOffset.clamp(0, nextText.length),
      extentOffset: nextExtentOffset.clamp(0, nextText.length),
    ),
    didChange: true,
  );
}

bool _selectionSpansMultipleLines(String text, int startOffset, int endOffset) {
  if (startOffset >= endOffset) {
    return false;
  }
  return text.substring(startOffset, endOffset).contains('\n');
}

int _spacesForNextTabStop(String text, int offset, int indentSpaces) {
  final lineStart = _lineStartOffset(text, offset);
  final column = offset - lineStart;
  final remainder = column % indentSpaces;
  return remainder == 0 ? indentSpaces : indentSpaces - remainder;
}

_EditorBlockCommentTarget _blockCommentTargetForSelection(
  String text,
  TextSelection selection,
) {
  if (!selection.isCollapsed) {
    final startOffset = math.min(selection.baseOffset, selection.extentOffset);
    final endOffset = math.max(selection.baseOffset, selection.extentOffset);
    return _EditorBlockCommentTarget(
      start: startOffset,
      end: endOffset,
      wasCollapsed: false,
    );
  }

  final lineStart = _lineStartOffset(text, selection.baseOffset);
  final lineEnd = _lineEndOffset(text, selection.baseOffset);
  final lineText = text.substring(lineStart, lineEnd);
  final contentStart = lineStart + _leadingIndentEnd(lineText);
  final contentEnd = _trimTrailingHorizontalWhitespaceEnd(
    text,
    contentStart,
    lineEnd,
  );
  return _EditorBlockCommentTarget(
    start: contentStart,
    end: contentEnd,
    wasCollapsed: true,
  );
}

int _lineStartOffset(String text, int offset) {
  if (offset <= 0) {
    return 0;
  }
  final boundedOffset = offset.clamp(0, text.length);
  final newlineOffset = text.lastIndexOf('\n', boundedOffset - 1);
  return newlineOffset < 0 ? 0 : newlineOffset + 1;
}

int _lineEndOffset(String text, int offset) {
  if (text.isEmpty) {
    return 0;
  }
  final boundedOffset = offset.clamp(0, text.length);
  final newlineOffset = text.indexOf('\n', boundedOffset);
  return newlineOffset < 0 ? text.length : newlineOffset;
}

int _effectiveBlockEndOffset(
  String text,
  int startOffset,
  int endOffset,
  bool isCollapsed,
) {
  if (text.isEmpty || isCollapsed || endOffset <= startOffset) {
    return endOffset;
  }
  if (endOffset == _lineStartOffset(text, endOffset)) {
    return math.max(startOffset, endOffset - 1);
  }
  return endOffset;
}

int _removableIndentWidth(String lineText, int indentSpaces) {
  final maxRemoval = math.min(indentSpaces, lineText.length);
  var removed = 0;
  while (removed < maxRemoval && lineText.codeUnitAt(removed) == 32) {
    removed += 1;
  }
  return removed;
}

String _leadingIndentation(String lineText) {
  final indentationEnd = _leadingIndentEnd(lineText);
  if (indentationEnd <= 0) {
    return '';
  }
  return lineText.substring(0, indentationEnd);
}

int _leadingIndentEnd(String lineText) {
  var offset = 0;
  while (offset < lineText.length && _isIndentChar(lineText.codeUnitAt(offset))) {
    offset += 1;
  }
  return offset;
}

bool _lineHasCommentPrefix(
  String lineText,
  int indentationEnd,
  String commentPrefix,
) {
  final prefixEnd = indentationEnd + commentPrefix.length;
  if (prefixEnd > lineText.length) {
    return false;
  }
  return lineText.substring(indentationEnd, prefixEnd) == commentPrefix;
}

bool _isIndentChar(int charCode) {
  return charCode == 32 || charCode == 9;
}

String? _unwrapBlockComment(
  String targetText, {
  required String blockCommentStart,
  required String blockCommentEnd,
}) {
  if (!targetText.startsWith(blockCommentStart) ||
      !targetText.endsWith(blockCommentEnd) ||
      targetText.length < blockCommentStart.length + blockCommentEnd.length) {
    return null;
  }
  var inner = targetText.substring(
    blockCommentStart.length,
    targetText.length - blockCommentEnd.length,
  );
  if (inner.startsWith('\n') && inner.endsWith('\n') && inner.length >= 2) {
    inner = inner.substring(1, inner.length - 1);
  } else {
    if (inner.startsWith(' ')) {
      inner = inner.substring(1);
    }
    if (inner.endsWith(' ')) {
      inner = inner.substring(0, inner.length - 1);
    }
  }
  return inner;
}

TextSelection _selectionForEditedRange(
  TextSelection originalSelection,
  int start,
  int end,
) {
  if (originalSelection.baseOffset <= originalSelection.extentOffset) {
    return TextSelection(baseOffset: start, extentOffset: end);
  }
  return TextSelection(baseOffset: end, extentOffset: start);
}

int _trimTrailingHorizontalWhitespaceEnd(String text, int start, int end) {
  var trimmedEnd = end;
  while (trimmedEnd > start && _isIndentChar(text.codeUnitAt(trimmedEnd - 1))) {
    trimmedEnd -= 1;
  }
  return trimmedEnd;
}

int? _trailingOpeningDelimiter(String text) {
  for (var index = text.length - 1; index >= 0; index -= 1) {
    final charCode = text.codeUnitAt(index);
    if (_isIndentChar(charCode)) {
      continue;
    }
    return switch (charCode) {
      123 || 91 || 40 => charCode,
      _ => null,
    };
  }
  return null;
}

int? _matchingClosingDelimiter(int openingDelimiter) {
  return switch (openingDelimiter) {
    123 => 125,
    91 => 93,
    40 => 41,
    _ => null,
  };
}

int? _leadingNonWhitespaceCharacter(String text) {
  for (var index = 0; index < text.length; index += 1) {
    final charCode = text.codeUnitAt(index);
    if (_isIndentChar(charCode)) {
      continue;
    }
    return charCode;
  }
  return null;
}

bool _shouldIncreaseIndentForLanguage(String language, String beforeCursor) {
  final trimmedBeforeCursor = beforeCursor.trimRight();
  if (trimmedBeforeCursor.isEmpty) {
    return false;
  }
  final logicalLine = trimmedBeforeCursor.trimLeft();
  if (language == 'python' && _pythonBlockOpener.hasMatch(logicalLine)) {
    return true;
  }
  if (_switchCaseBlockOpener.hasMatch(logicalLine)) {
    return _caseIndentLanguages.contains(language);
  }
  if (trimmedBeforeCursor.endsWith('=>')) {
    return _arrowIndentLanguages.contains(language);
  }
  return false;
}

final RegExp _pythonBlockOpener = RegExp(
  r'^(?:async\s+def|async\s+for|async\s+with|if|elif|else|for|while|try|except|finally|with|def|class|match|case)\b.*:\s*$',
);

final RegExp _switchCaseBlockOpener = RegExp(
  r'^(?:case\b.*|default)\s*:\s*$',
);

const Set<String> _caseIndentLanguages = <String>{
  'dart',
  'javascript',
  'typescript',
  'vue',
  'svelte',
  'astro',
};

const Set<String> _arrowIndentLanguages = <String>{
  'dart',
  'javascript',
  'typescript',
  'vue',
  'svelte',
  'astro',
};

String _spaces(int count) {
  if (count <= 0) {
    return '';
  }
  return List<String>.filled(count, ' ').join();
}
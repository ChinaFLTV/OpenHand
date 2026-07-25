import 'dart:convert';

import 'package:path/path.dart' as p;

import 'text_clip.dart';

const int kOpenHandMaxAncestorDirectoryDepth = 256;
const int kPortableFileNameMaxCodeUnits = 255;
const int kPortableFileNameMaxUtf8Bytes = 255;
const String _kEmptyPathError = 'path must not be empty.';
const String _kRelativePathError = 'path must be relative.';
const String _kParentTraversalError =
    'path must not traverse parent directories.';
const String _kNullBytePathError = 'path must not contain null bytes.';
final RegExp _portableFileNameUnsafeCharsPattern = RegExp(r'[^A-Za-z0-9._-]+');
final RegExp _displayFileNameUnsafeCharsPattern = RegExp(
  r'[\\/:*?"<>|\x00-\x1f\x7f]+',
);
final RegExp _reservedWindowsFileNamePattern = RegExp(
  r'^(?:con|prn|aux|nul|com[1-9¹²³]|lpt[1-9¹²³])(?:\..*)?$',
  caseSensitive: false,
);
final RegExp _whitespacePattern = RegExp(r'\s+');
final RegExp _replacementRunPattern = RegExp(r'_+');
final RegExp _boundaryReplacementPattern = RegExp(r'^_+|_+$');
final RegExp _trailingFileNameCharsPattern = RegExp(r'[ .]+$');

/// Returns true when [candidate] resolves to [parent] or a descendant of it.
///
/// Both paths are normalized before comparison. The helper intentionally does
/// not resolve symlinks; callers that need physical-path containment should
/// canonicalize before calling.
bool isPathWithinOrEqual(String parent, String candidate) {
  final normalizedParent = p.normalize(parent);
  final normalizedCandidate = p.normalize(candidate);
  return p.equals(normalizedParent, normalizedCandidate) ||
      p.isWithin(normalizedParent, normalizedCandidate);
}

/// Normalizes a user-supplied relative path and validates it stays relative.
String? safeRelativePathError(String relativePath) {
  final raw = relativePath.trim();
  if (raw.isEmpty) {
    return _kEmptyPathError;
  }
  if (raw.contains('\u0000')) {
    return _kNullBytePathError;
  }
  if (_hasAnyRootPrefix(raw)) {
    return _kRelativePathError;
  }
  if (_containsParentDirectorySegment(raw)) {
    return _kParentTraversalError;
  }
  final normalized = p.normalize(raw);
  if (normalized.isEmpty || normalized == '.') {
    return _kEmptyPathError;
  }
  if (_hasAnyRootPrefix(normalized)) {
    return _kRelativePathError;
  }
  if (_containsParentDirectorySegment(normalized)) {
    return _kParentTraversalError;
  }
  return null;
}

bool _hasAnyRootPrefix(String path) {
  return p.rootPrefix(path).isNotEmpty ||
      p.windows.rootPrefix(path).isNotEmpty ||
      p.url.rootPrefix(path).isNotEmpty;
}

bool _containsParentDirectorySegment(String path) {
  return p.split(path).contains('..') ||
      p.windows.split(path).contains('..') ||
      p.url.split(path).contains('..');
}

/// Returns a display path relative to [from] only when the target stays inside
/// that directory. Falls back to the normalized absolute path otherwise.
String safeRelativePathForDisplay(String target, {required String from}) {
  final normalizedFrom = p.normalize(from);
  final normalizedTarget = p.normalize(target);
  if (!isPathWithinOrEqual(normalizedFrom, normalizedTarget)) {
    return normalizedTarget;
  }
  return p.relative(normalizedTarget, from: normalizedFrom);
}

/// Returns [startDirectory] and its parents, guarded by a max-depth and a
/// visited set so malformed path inputs cannot create an unbounded traversal.
List<String> ancestorDirectoriesFrom(
  String startDirectory, {
  bool rootFirst = false,
  int maxDepth = kOpenHandMaxAncestorDirectoryDepth,
}) {
  final raw = startDirectory.trim();
  if (raw.isEmpty || maxDepth <= 0) return const <String>[];
  final limit = maxDepth > kOpenHandMaxAncestorDirectoryDepth
      ? kOpenHandMaxAncestorDirectoryDepth
      : maxDepth;
  final directories = <String>[];
  final seen = <String>{};
  var current = p.normalize(raw);

  while (directories.length < limit && seen.add(current)) {
    directories.add(current);
    final parent = p.dirname(current);
    if (parent == current) break;
    current = parent;
  }

  if (!rootFirst) return directories;
  return directories.reversed.toList(growable: false);
}

/// 判断字符串是否为可跨平台使用的单个文件名片段。
bool isPortableFileNamePart(
  String value, {
  int maxCodeUnits = kPortableFileNameMaxCodeUnits,
  int maxUtf8Bytes = kPortableFileNameMaxUtf8Bytes,
}) {
  if (value.isEmpty ||
      maxCodeUnits <= 0 ||
      maxUtf8Bytes <= 0 ||
      value.length > maxCodeUnits ||
      value == '.' ||
      value == '..' ||
      value.endsWith(' ') ||
      value.endsWith('.') ||
      _displayFileNameUnsafeCharsPattern.hasMatch(value) ||
      _reservedWindowsFileNamePattern.hasMatch(value)) {
    return false;
  }
  return utf8.encode(value).length <= maxUtf8Bytes;
}

/// 清理单个跨平台文件名或目录名片段，不处理完整路径。
String sanitizePortableFileNamePart(
  String input, {
  String fallback = 'file',
  int? maxCharacters = 120,
  int maxUtf8Bytes = kPortableFileNameMaxUtf8Bytes,
  bool allowWhitespace = false,
  bool collapseReplacement = false,
  bool trimBoundaryReplacement = false,
}) {
  final sanitized = _sanitizePortableFileNamePart(
    input,
    maxCharacters: maxCharacters,
    maxUtf8Bytes: maxUtf8Bytes,
    allowWhitespace: allowWhitespace,
    collapseReplacement: collapseReplacement,
    trimBoundaryReplacement: trimBoundaryReplacement,
  );
  if (sanitized.isNotEmpty) return sanitized;
  return _sanitizePortableFileNamePart(
    fallback,
    maxCharacters: maxCharacters,
    maxUtf8Bytes: maxUtf8Bytes,
    allowWhitespace: allowWhitespace,
    collapseReplacement: collapseReplacement,
    trimBoundaryReplacement: trimBoundaryReplacement,
  );
}

String _sanitizePortableFileNamePart(
  String input, {
  required int? maxCharacters,
  required int maxUtf8Bytes,
  required bool allowWhitespace,
  required bool collapseReplacement,
  required bool trimBoundaryReplacement,
}) {
  if (maxCharacters != null && maxCharacters <= 0 || maxUtf8Bytes <= 0) {
    return '';
  }
  var sanitized = input.replaceAll(
    allowWhitespace
        ? _displayFileNameUnsafeCharsPattern
        : _portableFileNameUnsafeCharsPattern,
    '_',
  );
  if (allowWhitespace) {
    sanitized = sanitized.replaceAll(_whitespacePattern, ' ').trim();
  }
  if (collapseReplacement) {
    sanitized = sanitized.replaceAll(_replacementRunPattern, '_');
  }
  if (trimBoundaryReplacement) {
    sanitized = sanitized.replaceAll(_boundaryReplacementPattern, '');
  }
  if (maxCharacters != null) {
    sanitized = clipText(sanitized, maxCharacters, suffix: '');
  }
  final utf8PrefixLength = safeUtf8PrefixCodeUnits(sanitized, maxUtf8Bytes);
  sanitized = sanitized
      .substring(0, utf8PrefixLength)
      .replaceFirst(_trailingFileNameCharsPattern, '');
  if (_reservedWindowsFileNamePattern.hasMatch(sanitized)) {
    sanitized = '_$sanitized';
    final safeLength = safeUtf8PrefixCodeUnits(sanitized, maxUtf8Bytes);
    sanitized = sanitized.substring(0, safeLength);
    if (maxCharacters != null) {
      sanitized = clipText(sanitized, maxCharacters, suffix: '');
    }
  }
  return sanitized == '.' || sanitized == '..' ? '' : sanitized;
}

import 'package:path/path.dart' as p;

import 'text_clip.dart';

const int kOpenHandMaxAncestorDirectoryDepth = 256;
const String _kEmptyPathError = 'path must not be empty.';
const String _kRelativePathError = 'path must be relative.';
const String _kParentTraversalError =
    'path must not traverse parent directories.';
const String _kNullBytePathError = 'path must not contain null bytes.';
final RegExp _portableFileNameUnsafeCharsPattern = RegExp(r'[^A-Za-z0-9._-]+');
final RegExp _displayFileNameUnsafeCharsPattern = RegExp(
  r'[\\/:*?"<>|\x00-\x1f]+',
);
final RegExp _whitespacePattern = RegExp(r'\s+');
final RegExp _replacementRunPattern = RegExp(r'_+');
final RegExp _boundaryReplacementPattern = RegExp(r'^_+|_+$');

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

/// Sanitizes a single portable file or directory name segment.
///
/// This helper intentionally handles only a basename-like segment, not a full
/// path. Use [safeRelativePathError] for user-supplied relative paths.
String sanitizePortableFileNamePart(
  String input, {
  String fallback = 'file',
  int? maxCharacters = 120,
  bool allowWhitespace = false,
  bool collapseReplacement = false,
  bool trimBoundaryReplacement = false,
}) {
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
  if (sanitized.isEmpty) return fallback;
  if (maxCharacters == null) return sanitized;
  if (maxCharacters <= 0) return fallback;
  return clipText(sanitized, maxCharacters, suffix: '');
}

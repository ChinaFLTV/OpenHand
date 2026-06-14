import 'package:path/path.dart' as p;

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
    return 'path must not be empty.';
  }
  if (p.isAbsolute(raw)) {
    return 'path must be relative.';
  }
  if (p.split(raw).contains('..')) {
    return 'path must not traverse parent directories.';
  }
  final normalized = p.normalize(raw);
  if (normalized.isEmpty || normalized == '.') {
    return 'path must not be empty.';
  }
  if (p.isAbsolute(normalized)) {
    return 'path must be relative.';
  }
  if (p.split(normalized).contains('..')) {
    return 'path must not traverse parent directories.';
  }
  return null;
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

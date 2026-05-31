import 'dart:io';

import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as p;

import '../../../app/support/openhand_paths.dart';

import '../../ai/index.dart';

const int _resolvedMessagePathCacheLimit = 512;

final Map<String, MessageResolvedPath?> _resolvedMessagePathCache =
    <String, MessageResolvedPath?>{};
final RegExp _detectedFilePathTrailingPattern = RegExp(
  r'''[),.;:!?\]\}'"”。，？！；：“”‘’]+$''',
);
final RegExp _detectedStandaloneFileNamePattern = RegExp(
  r'''^(?:\.[^\s<>()[\]{}'"*?:;|/`]+|[^\s<>()[\]{}'"*?:;|/`]+\.[a-zA-Z0-9]+)$''',
);

/// Matches strings that begin with a domain-qualified path segment, e.g.
/// `gitee.com/org/repo`, `github.com/user/project`, `golang.org/x/tools`.
/// These are Go/Java/Maven-style import paths and should NOT be treated as
/// local file paths.  The pattern requires a domain with a TLD-like suffix
/// (2+ letters after the final dot) followed by `/`.
///
/// Examples that match:
/// - `github.com/user/project` (domain.TLD/path)
/// - `gitee.com/org/repo` (domain.TLD/path)
/// - `golang.org/x/tools` (domain.TLD/path)
/// - `git.zuoyebang.cc/org/repo` (subdomain.domain.TLD/path)
/// - `pkg.go.dev/golang.org/x/tools` (multi-level domain)
final RegExp _domainQualifiedPathPattern = RegExp(
  r'^[A-Za-z0-9][-A-Za-z0-9]*(?:\.[A-Za-z0-9][-A-Za-z0-9]*)*\.[A-Za-z]{2,}/',
);

List<String> messageFilePathRoots(
  AiSessionEnvironment environment, {
  String? workingDirectory,
}) {
  final roots = <String>{};

  void addRoot(String? rawPath) {
    if (rawPath == null) {
      return;
    }
    final trimmed = rawPath.trim();
    if (trimmed.isEmpty) {
      return;
    }
    roots.add(p.normalize(trimmed));
  }

  bool isVirtualStorePath(String path) {
    return path.contains('://');
  }

  void addParentRoot(String? rawPath) {
    if (rawPath == null) {
      return;
    }
    final trimmed = rawPath.trim();
    if (trimmed.isEmpty || isVirtualStorePath(trimmed)) {
      return;
    }
    addRoot(p.dirname(trimmed));
  }

  addRoot(workingDirectory);
  addRoot(Directory.current.path);
  addRoot(environment.applicationDirectory);
  addParentRoot(environment.settingsFilePath);
  addParentRoot(environment.mcpServersFilePath);
  addParentRoot(environment.userMemoryFilePath);
  addRoot(environment.skillsStoragePath);
  addRoot(environment.sessionsDirectoryPath);
  addRoot(environment.homeDirectory);
  return roots.toList(growable: false);
}

MessageResolvedPath? resolveExistingMessagePath(
  String rawPath,
  List<String> candidateRoots,
) {
  final displayPath = rawPath.trim();
  if (displayPath.isEmpty || !looksLikeResolvableMessagePath(displayPath)) {
    return null;
  }
  final cacheKey = '${candidateRoots.join('|')}::$displayPath';
  if (_resolvedMessagePathCache.containsKey(cacheKey)) {
    return _resolvedMessagePathCache[cacheKey];
  }

  final candidates = <String>{};
  if (displayPath == '~' ||
      displayPath.startsWith('~/') ||
      displayPath.startsWith(r'~\')) {
    candidates.add(
      OpenHandPaths.normalizePath(
        displayPath,
        defaultPath: OpenHandPaths.homeDirectoryPath(),
      ),
    );
  } else if (looksLikeAbsoluteMessagePath(displayPath)) {
    candidates.add(p.normalize(displayPath));
  } else {
    for (final root in candidateRoots) {
      if (root.trim().isEmpty) {
        continue;
      }
      candidates.add(p.normalize(p.join(root, displayPath)));
    }
  }

  MessageResolvedPath? resolved;
  for (final candidate in candidates) {
    final entityType = FileSystemEntity.typeSync(candidate);
    if (entityType == FileSystemEntityType.notFound) {
      continue;
    }
    final isDirectory = entityType == FileSystemEntityType.directory;
    resolved = MessageResolvedPath(
      displayPath: displayPath,
      resolvedPath: p.normalize(candidate),
      isDirectory: isDirectory,
    );
    break;
  }
  _rememberResolvedMessagePath(cacheKey, resolved);
  return resolved;
}

void _rememberResolvedMessagePath(String cacheKey, MessageResolvedPath? value) {
  if (_resolvedMessagePathCache.length >= _resolvedMessagePathCacheLimit) {
    _resolvedMessagePathCache.remove(_resolvedMessagePathCache.keys.first);
  }
  _resolvedMessagePathCache[cacheKey] = value;
}

/// Synchronous cache probe used by widgets that want to avoid spinning up
/// a `FutureBuilder` / extra frame when the path has already been resolved
/// (either by an earlier async lookup or by the inline markdown syntax).
///
/// Returns a record of `(hit, value)` where `hit` indicates whether the
/// cache contained an entry (regardless of whether that entry was `null`
/// for "does not exist"); callers can use `hit` to distinguish a cache miss
/// from a genuinely unresolved path.
({bool hit, MessageResolvedPath? value}) lookupResolvedMessagePathFromCache(
  String rawPath,
  List<String> candidateRoots,
) {
  final displayPath = rawPath.trim();
  if (displayPath.isEmpty) {
    return (hit: false, value: null);
  }
  final cacheKey = '${candidateRoots.join('|')}::$displayPath';
  if (_resolvedMessagePathCache.containsKey(cacheKey)) {
    return (hit: true, value: _resolvedMessagePathCache[cacheKey]);
  }
  return (hit: false, value: null);
}

bool looksLikeAbsoluteMessagePath(String path) {
  return path.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path);
}

bool looksLikeResolvableMessagePath(String path) {
  final normalized = path.trim();
  if (normalized.isEmpty) {
    return false;
  }
  // Reject strings that look like domain-qualified package/import paths
  // (e.g. "gitee.com/org/repo/pkg" or "github.com/user/project") — these
  // are not local file system paths and should never become capsules.
  if (_domainQualifiedPathPattern.hasMatch(normalized)) {
    return false;
  }
  if (normalized == '~' ||
      normalized.startsWith('~/') ||
      normalized.startsWith(r'~\') ||
      normalized.startsWith('./') ||
      normalized.startsWith('../') ||
      looksLikeAbsoluteMessagePath(normalized) ||
      normalized.contains('/') ||
      normalized.contains(r'\')) {
    return true;
  }
  return _detectedStandaloneFileNamePattern.hasMatch(normalized);
}

MessageResolvedPath? resolveMarkdownMessageLinkPath(
  String? href,
  List<String> candidateRoots,
) {
  final normalizedHref = (href ?? '').trim();
  if (normalizedHref.isEmpty) {
    return null;
  }
  if (normalizedHref.startsWith('file://')) {
    try {
      final filePath = Uri.parse(normalizedHref).toFilePath();
      return resolveExistingMessagePath(filePath, candidateRoots);
    } catch (_) {
      return null;
    }
  }
  return resolveExistingMessagePath(normalizedHref, candidateRoots);
}

Uri? parseSupportedMessageLinkUri(String? href) {
  final normalizedHref = (href ?? '').trim();
  if (normalizedHref.isEmpty) {
    return null;
  }
  final uri = Uri.tryParse(normalizedHref);
  if (uri == null || !uri.hasScheme) {
    return null;
  }
  final scheme = uri.scheme.toLowerCase();
  if (scheme == 'http' ||
      scheme == 'https' ||
      scheme == 'mailto' ||
      scheme == 'file') {
    return uri;
  }
  return null;
}

class MessageResolvedPath {
  const MessageResolvedPath({
    required this.displayPath,
    required this.resolvedPath,
    required this.isDirectory,
  });

  final String displayPath;
  final String resolvedPath;
  final bool isDirectory;
}

Future<MessageResolvedPath?> resolveExistingMessagePathAsync(
  String rawPath,
  List<String> candidateRoots,
) async {
  final displayPath = rawPath.trim();
  if (displayPath.isEmpty || !looksLikeResolvableMessagePath(displayPath)) {
    return null;
  }
  final cacheKey = '${candidateRoots.join('|')}::$displayPath';
  if (_resolvedMessagePathCache.containsKey(cacheKey)) {
    return _resolvedMessagePathCache[cacheKey];
  }

  final candidates = <String>{};
  if (displayPath == '~' ||
      displayPath.startsWith('~/') ||
      displayPath.startsWith(r'~\')) {
    candidates.add(
      OpenHandPaths.normalizePath(
        displayPath,
        defaultPath: OpenHandPaths.homeDirectoryPath(),
      ),
    );
  } else if (looksLikeAbsoluteMessagePath(displayPath)) {
    candidates.add(p.normalize(displayPath));
  } else {
    for (final root in candidateRoots) {
      if (root.trim().isEmpty) {
        continue;
      }
      candidates.add(p.normalize(p.join(root, displayPath)));
    }
  }

  MessageResolvedPath? resolved;
  for (final candidate in candidates) {
    final type = await FileSystemEntity.type(candidate);
    if (type == FileSystemEntityType.notFound) {
      continue;
    }
    final isDirectory = await FileSystemEntity.isDirectory(candidate);
    resolved = MessageResolvedPath(
      displayPath: displayPath,
      resolvedPath: p.normalize(candidate),
      isDirectory: isDirectory,
    );
    break;
  }
  _rememberResolvedMessagePath(cacheKey, resolved);
  return resolved;
}

class MessagePathCodeSyntax extends md.InlineSyntax {
  MessagePathCodeSyntax({required this.candidateRoots})
    : super(r'(`+(?!`))((?:.|\n)*?)(?<!`)\1(?!`)');

  final List<String> candidateRoots;

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final text = match[2] ?? '';
    final codeElement = md.Element.text('code', text);

    final normalizedPath = text.replaceFirst(
      _detectedFilePathTrailingPattern,
      '',
    );

    if (normalizedPath.isEmpty ||
        !looksLikeResolvableMessagePath(normalizedPath)) {
      parser.addNode(codeElement);
      return true;
    }

    final trailing = text.substring(normalizedPath.length);
    final resolvedPathCacheKey = '${candidateRoots.join('|')}::$normalizedPath';

    if (_resolvedMessagePathCache.containsKey(resolvedPathCacheKey)) {
      final resolvedPath = _resolvedMessagePathCache[resolvedPathCacheKey];
      if (resolvedPath == null) {
        parser.addNode(codeElement);
        return true;
      }
      parser.addNode(
        md.Element.text('openhand-file-resolved', resolvedPath.displayPath)
          ..attributes['resolved_path'] = resolvedPath.resolvedPath
          ..attributes['entity_type'] = resolvedPath.isDirectory
              ? 'directory'
              : 'file',
      );
      if (trailing.isNotEmpty) {
        parser.addNode(md.Text(trailing));
      }
      return true;
    }

    parser.addNode(
      md.Element.text('openhand-file-pending', text)
        ..attributes['normalized_path'] = normalizedPath
        ..attributes['candidate_roots'] = candidateRoots.join('\r')
        ..attributes['trailing'] = trailing
        ..attributes['is_code_span'] = 'true',
    );
    return true;
  }
}

class MessageFilePathSyntax extends md.InlineSyntax {
  MessageFilePathSyntax({required this.candidateRoots})
    : super(
        r'''(^|[\s>"'`：，。、；！？（）【】《》…—]|[\u4E00-\u9FFF]|(?<!\])\()((?!https?:\/\/|mailto:)(?:(?:~\/|\.{1,2}\/|\/|[A-Za-z]:[\\/]|(?:[^\s<>()[\]{}'"*?:;|/`]+[\\/]))[^\s<>()[\]{}'"`]+|(?:\.[^\s<>()[\]{}'"*?:;|/`]+|[^\s<>()[\]{}'"*?:;|/`]+\.[a-zA-Z0-9]+)))''',
      );

  final List<String> candidateRoots;

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final fullMatch = match[0] ?? '';
    final prefix = match[1] ?? '';
    final matchedPath = match[2] ?? '';
    final normalizedPath = matchedPath.replaceFirst(
      _detectedFilePathTrailingPattern,
      '',
    );
    if (normalizedPath.isEmpty ||
        !looksLikeResolvableMessagePath(normalizedPath)) {
      parser.addNode(md.Text(fullMatch));
      return true;
    }
    final trailing = matchedPath.substring(normalizedPath.length);

    final resolvedPathCacheKey = '${candidateRoots.join('|')}::$normalizedPath';
    if (_resolvedMessagePathCache.containsKey(resolvedPathCacheKey)) {
      final resolvedPath = _resolvedMessagePathCache[resolvedPathCacheKey];
      if (resolvedPath == null) {
        parser.addNode(md.Text(fullMatch));
        return true;
      }
      if (prefix.isNotEmpty) {
        parser.addNode(md.Text(prefix));
      }
      parser.addNode(
        md.Element.text('openhand-file-resolved', resolvedPath.displayPath)
          ..attributes['resolved_path'] = resolvedPath.resolvedPath
          ..attributes['entity_type'] = resolvedPath.isDirectory
              ? 'directory'
              : 'file',
      );
      if (trailing.isNotEmpty) {
        parser.addNode(md.Text(trailing));
      }
      return true;
    }

    if (prefix.isNotEmpty) {
      parser.addNode(md.Text(prefix));
    }
    parser.addNode(
      md.Element.text('openhand-file-pending', matchedPath)
        ..attributes['normalized_path'] = normalizedPath
        ..attributes['candidate_roots'] = candidateRoots.join('\r')
        ..attributes['trailing'] = trailing
        ..attributes['is_code_span'] = 'false',
    );
    return true;
  }
}

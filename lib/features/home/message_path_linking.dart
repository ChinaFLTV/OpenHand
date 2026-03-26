import 'dart:io';

import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as p;

import '../../app/support/openhand_paths.dart';
import '../ai/model/ai_session.dart';

const int _resolvedMessagePathCacheLimit = 512;

final Map<String, MessageResolvedPath> _resolvedMessagePathCache =
    <String, MessageResolvedPath>{};
final RegExp _detectedFilePathTrailingPattern = RegExp(
  r'''[),.;:!?\]\}'"]+$''',
);
final RegExp _detectedStandaloneFileNamePattern = RegExp(
  r'''^(?:\.[A-Za-z0-9][A-Za-z0-9._-]*|[A-Za-z0-9_][A-Za-z0-9._-]*\.[A-Za-z0-9][A-Za-z0-9._-]*)$''',
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

  void addParentRoot(String? rawPath) {
    if (rawPath == null) {
      return;
    }
    final trimmed = rawPath.trim();
    if (trimmed.isEmpty) {
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
  final cachedPath = _resolvedMessagePathCache[cacheKey];
  if (cachedPath != null) {
    final cachedEntityType = FileSystemEntity.typeSync(
      cachedPath.resolvedPath,
      followLinks: true,
    );
    if (cachedEntityType != FileSystemEntityType.notFound) {
      return cachedPath;
    }
    _resolvedMessagePathCache.remove(cacheKey);
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
  }
  if (looksLikeAbsoluteMessagePath(displayPath)) {
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
    final entityType = FileSystemEntity.typeSync(candidate, followLinks: true);
    if (entityType == FileSystemEntityType.notFound) {
      continue;
    }
    final isDirectory =
        entityType == FileSystemEntityType.directory ||
        Directory(candidate).existsSync();
    resolved = MessageResolvedPath(
      displayPath: displayPath,
      resolvedPath: p.normalize(candidate),
      isDirectory: isDirectory,
    );
    break;
  }
  if (resolved != null) {
    _rememberResolvedMessagePath(cacheKey, resolved);
  }
  return resolved;
}

void _rememberResolvedMessagePath(String cacheKey, MessageResolvedPath value) {
  if (_resolvedMessagePathCache.length >= _resolvedMessagePathCacheLimit) {
    _resolvedMessagePathCache.remove(_resolvedMessagePathCache.keys.first);
  }
  _resolvedMessagePathCache[cacheKey] = value;
}

bool looksLikeAbsoluteMessagePath(String path) {
  return path.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path);
}

bool looksLikeResolvableMessagePath(String path) {
  final normalized = path.trim();
  if (normalized.isEmpty) {
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

class MessageFilePathSyntax extends md.InlineSyntax {
  MessageFilePathSyntax({required this.candidateRoots})
    : super(
        r'''(^|[\s(>"'])((?:~\/|\.{1,2}\/|\/|[A-Za-z]:[\\/]|(?:[A-Za-z0-9_.-]+[\\/]))[^\s<>()\[\]{}]+|(?:\.[A-Za-z0-9][A-Za-z0-9._-]*|[A-Za-z0-9_][A-Za-z0-9._-]*\.[A-Za-z0-9][A-Za-z0-9._-]*))''',
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
    final resolvedPath = resolveExistingMessagePath(
      normalizedPath,
      candidateRoots,
    );
    if (resolvedPath == null) {
      parser.addNode(md.Text(fullMatch));
      return true;
    }
    if (prefix.isNotEmpty) {
      parser.addNode(md.Text(prefix));
    }
    parser.addNode(
      md.Element.text('openhand-file', resolvedPath.displayPath)
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
}

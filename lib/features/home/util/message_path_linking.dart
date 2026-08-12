import 'dart:async';
import 'dart:io';

import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as p;

import '../../../app/support/openhand_paths.dart';
import '../../../shared/util/async_concurrency.dart';
import '../../ai/index.dart';

const int _resolvedMessagePathCacheLimit = 512;
const int _messagePathProbeCandidateLimit = 64;
const Duration _messagePathProbeIdleTimeout = Duration(seconds: 3);
const Duration _messagePathProbeTotalTimeout = Duration(seconds: 10);
const String messageResolvedPathElementTag = 'openhand-file-resolved';
const String messagePendingPathElementTag = 'openhand-file-pending';

const String _resolvedPathAttribute = 'resolved_path';
const String _entityTypeAttribute = 'entity_type';
const String _normalizedPathAttribute = 'normalized_path';
const String _candidateRootsAttribute = 'candidate_roots';
const String _trailingAttribute = 'trailing';
const String _isCodeSpanAttribute = 'is_code_span';

final Map<String, MessageResolvedPath?> _resolvedMessagePathCache =
    <String, MessageResolvedPath?>{};
final RegExp _detectedFilePathTrailingPattern = RegExp(
  r'''[),.;:!?\]\}'"”。，？！；：“”‘’]+$''',
);
final RegExp _detectedStandaloneFileNamePattern = RegExp(
  r'''^(?:\.[^\s<>()[\]{}'"*?:;|/`]+|[^\s<>()[\]{}'"*?:;|/`]+\.[a-zA-Z0-9]+)$''',
);

/// 匹配域名开头的包导入路径，避免将其误识别为本地文件路径。
final RegExp _windowsDriveRootPattern = RegExp(r'^[A-Za-z]:[\\/]');

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
  final request = _prepareMessagePathResolution(rawPath, candidateRoots);
  if (request == null) return null;
  return _resolvedMessagePathCache[request.cacheKey];
}

/// 返回首个规范化候选路径，不访问磁盘。
String? firstMessagePathCandidate(String rawPath, List<String> candidateRoots) {
  final request = _prepareMessagePathResolution(rawPath, candidateRoots);
  return request?.candidates.firstOrNull;
}

({String displayPath, String cacheKey, Set<String> candidates})?
_prepareMessagePathResolution(String rawPath, List<String> candidateRoots) {
  final displayPath = rawPath.trim();
  if (displayPath.isEmpty || !looksLikeResolvableMessagePath(displayPath)) {
    return null;
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
      if (root.trim().isEmpty) continue;
      candidates.add(p.normalize(p.join(root, displayPath)));
    }
  }
  return (
    displayPath: displayPath,
    cacheKey: _resolvedMessagePathCacheKey(displayPath, candidateRoots),
    candidates: candidates,
  );
}

String _resolvedMessagePathCacheKey(
  String displayPath,
  List<String> candidateRoots,
) => '${candidateRoots.join('|')}::$displayPath';

void _rememberResolvedMessagePath(String cacheKey, MessageResolvedPath? value) {
  if (_resolvedMessagePathCache.length >= _resolvedMessagePathCacheLimit) {
    _resolvedMessagePathCache.remove(_resolvedMessagePathCache.keys.first);
  }
  _resolvedMessagePathCache[cacheKey] = value;
}

/// 同步读取路径缓存，避免已解析路径再次创建异步构建帧。
/// [hit] 用于区分缓存未命中和已确认不存在。
({bool hit, MessageResolvedPath? value}) lookupResolvedMessagePathFromCache(
  String rawPath,
  List<String> candidateRoots,
) {
  final displayPath = rawPath.trim();
  if (displayPath.isEmpty) {
    return (hit: false, value: null);
  }
  final cacheKey = _resolvedMessagePathCacheKey(displayPath, candidateRoots);
  if (_resolvedMessagePathCache.containsKey(cacheKey)) {
    return (hit: true, value: _resolvedMessagePathCache[cacheKey]);
  }
  return (hit: false, value: null);
}

bool looksLikeAbsoluteMessagePath(String path) {
  return path.startsWith('/') || _windowsDriveRootPattern.hasMatch(path);
}

bool looksLikeResolvableMessagePath(String path) {
  final normalized = path.trim();
  if (normalized.isEmpty) {
    return false;
  }
  // 域名开头的包导入路径不是本地文件，不能渲染为路径胶囊。
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

typedef MessagePendingPathElement = ({
  String normalizedPath,
  List<String> candidateRoots,
  String fullMatch,
  String trailing,
  bool isCodeSpan,
});

MessageResolvedPath messageResolvedPathFromElement(md.Element element) {
  return MessageResolvedPath(
    displayPath: element.textContent.trim(),
    resolvedPath: (element.attributes[_resolvedPathAttribute] ?? '').trim(),
    isDirectory:
        (element.attributes[_entityTypeAttribute] ?? '').trim() == 'directory',
  );
}

MessagePendingPathElement messagePendingPathFromElement(md.Element element) {
  return (
    normalizedPath: element.attributes[_normalizedPathAttribute] ?? '',
    candidateRoots: (element.attributes[_candidateRootsAttribute] ?? '').split(
      '\r',
    ),
    fullMatch: element.textContent,
    trailing: element.attributes[_trailingAttribute] ?? '',
    isCodeSpan: element.attributes[_isCodeSpanAttribute] == 'true',
  );
}

md.Element _resolvedMessagePathElement(MessageResolvedPath path) {
  return md.Element.text(messageResolvedPathElementTag, path.displayPath)
    ..attributes[_resolvedPathAttribute] = path.resolvedPath
    ..attributes[_entityTypeAttribute] = path.isDirectory
        ? 'directory'
        : 'file';
}

md.Element _pendingMessagePathElement({
  required String text,
  required String normalizedPath,
  required List<String> candidateRoots,
  required String trailing,
  required bool isCodeSpan,
}) {
  return md.Element.text(messagePendingPathElementTag, text)
    ..attributes[_normalizedPathAttribute] = normalizedPath
    ..attributes[_candidateRootsAttribute] = candidateRoots.join('\r')
    ..attributes[_trailingAttribute] = trailing
    ..attributes[_isCodeSpanAttribute] = '$isCodeSpan';
}

Future<MessageResolvedPath?> resolveExistingMessagePathAsync(
  String rawPath,
  List<String> candidateRoots,
) async {
  final request = _prepareMessagePathResolution(rawPath, candidateRoots);
  if (request == null) return null;
  final (:displayPath, :cacheKey, :candidates) = request;
  if (_resolvedMessagePathCache.containsKey(cacheKey)) {
    return _resolvedMessagePathCache[cacheKey];
  }

  MessageResolvedPath? resolved;
  final deadline = MonotonicDeadline(
    _messagePathProbeTotalTimeout,
    timeoutMessage: '消息路径探测超过总时限。',
  );
  try {
    for (final candidate in candidates.take(_messagePathProbeCandidateLimit)) {
      final remaining = deadline.remainingOrNull();
      if (remaining == null) break;
      final timeout = remaining < _messagePathProbeIdleTimeout
          ? remaining
          : _messagePathProbeIdleTimeout;
      FileSystemEntityType type;
      try {
        type = await FileSystemEntity.type(candidate).timeout(timeout);
      } on FileSystemException {
        continue;
      } on TimeoutException {
        continue;
      }
      if (type == FileSystemEntityType.notFound) continue;
      resolved = MessageResolvedPath(
        displayPath: displayPath,
        resolvedPath: p.normalize(candidate),
        isDirectory: type == FileSystemEntityType.directory,
      );
      break;
    }
  } finally {
    deadline.stop();
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
    final resolvedPathCacheKey = _resolvedMessagePathCacheKey(
      normalizedPath,
      candidateRoots,
    );

    if (_resolvedMessagePathCache.containsKey(resolvedPathCacheKey)) {
      final resolvedPath = _resolvedMessagePathCache[resolvedPathCacheKey];
      if (resolvedPath == null) {
        parser.addNode(codeElement);
        return true;
      }
      parser.addNode(_resolvedMessagePathElement(resolvedPath));
      if (trailing.isNotEmpty) {
        parser.addNode(md.Text(trailing));
      }
      return true;
    }

    parser.addNode(
      _pendingMessagePathElement(
        text: text,
        normalizedPath: normalizedPath,
        candidateRoots: candidateRoots,
        trailing: trailing,
        isCodeSpan: true,
      ),
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
      parser.addNode(_resolvedMessagePathElement(resolvedPath));
      if (trailing.isNotEmpty) {
        parser.addNode(md.Text(trailing));
      }
      return true;
    }

    if (prefix.isNotEmpty) {
      parser.addNode(md.Text(prefix));
    }
    parser.addNode(
      _pendingMessagePathElement(
        text: matchedPath,
        normalizedPath: normalizedPath,
        candidateRoots: candidateRoots,
        trailing: trailing,
        isCodeSpan: false,
      ),
    );
    return true;
  }
}

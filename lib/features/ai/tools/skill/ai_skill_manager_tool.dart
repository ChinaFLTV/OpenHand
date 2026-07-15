import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../../../../app/support/silent_log.dart';
import '../../../../shared/db/atomic_file_operations.dart';
import '../../../../shared/util/bounded_delete.dart';
import '../../../../shared/util/bounded_file_io.dart';
import '../../../../shared/util/directory_cleanup.dart';
import '../../../../shared/util/path_safety.dart';
import '../../../../shared/util/physical_path_safety.dart';
import '../../service/runtime/ai_tool_runtime_service.dart';
import '../ai_tool.dart';
import '../ai_tool_execution_context.dart';
import '../ai_tool_utils.dart';

/// SkillManager tool — manages AI skills on disk.
///
/// Supports the following actions (specified via `args['action']`):
/// - `create`      : create a new skill directory with SKILL.md
/// - `edit`        : rewrite SKILL.md of an existing skill
/// - `delete`      : remove a skill directory (and its empty category parent)
/// - `patch`       : substring replace inside SKILL.md (or a sub-file);
///                   unique match required unless `replace_all == true`.
/// - `write_file`  : create/overwrite a file in a whitelisted sub-directory
///                   (references/templates/scripts/assets) of a skill.
/// - `remove_file` : remove a file under a skill, cleaning empty parent dirs
///                   without deleting the skill root itself.
///
/// Layout: `<skillsDir>/[<category>/]<name>/SKILL.md`.
class AiSkillManagerTool extends AiTool {
  AiSkillManagerTool({required this.skillsDirProvider});

  final String Function() skillsDirProvider;

  static const String _toolName = 'SkillManager';
  static const int _maxNameLength = 64;
  static const int _maxDescriptionLength = 1024;
  static const int _maxSkillScanEntities = 5000;
  static const BoundedDeletePolicy _skillDeletePolicy = BoundedDeletePolicy(
    maxEntries: _maxSkillScanEntities,
    maxDepth: 64,
    totalTimeout: Duration(minutes: 1),
  );
  static const Duration _skillScanIdleTimeout = Duration(seconds: 3);
  static const Duration _skillScanTotalTimeout = Duration(seconds: 10);
  static const int _maxSidecarContentLength = 2 * 1024 * 1024;
  static const List<String> _supportedActions = <String>[
    'create',
    'edit',
    'delete',
    'patch',
    'write_file',
    'remove_file',
  ];
  int maxSkillContentLength = 100000;
  static final RegExp _nameRegex = RegExp(r'^[a-z0-9][a-z0-9._-]*$');
  static const Set<String> _allowedWriteSubdirs = <String>{
    'references',
    'templates',
    'scripts',
    'assets',
  };

  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.skillManager;

  /// This tool performs deletions, so it is destructive.
  @override
  bool get isDestructive => true;

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    return run(context.decodedArguments);
  }

  /// Direct entry point for callers that already have decoded arguments.
  Future<AiToolExecutionResult> run(Map<String, Object?> args) async {
    final startedAt = Stopwatch()..start();
    final action = AiToolUtils.readString(args['action']);
    if (action.isEmpty) {
      return AiToolUtils.invalidResult(
        _toolName,
        'action is required (one of: ${_supportedActions.join(', ')}).',
      );
    }

    final skillsRoot = _resolveSkillsRoot();
    if (skillsRoot == null) {
      return AiToolUtils.invalidResult(
        _toolName,
        'skills directory is not configured.',
      );
    }
    if (!_supportedActions.contains(action)) {
      return AiToolUtils.invalidResult(_toolName, 'Unknown action: $action.');
    }

    final name = AiToolUtils.readString(args['name']);
    final nameError = _validateName(name);
    if (nameError != null) {
      return AiToolUtils.invalidResult(_toolName, nameError);
    }

    try {
      switch (action) {
        case 'create':
          return await _create(args, skillsRoot, name, startedAt);
        case 'edit':
          return await _edit(args, skillsRoot, name, startedAt);
        case 'delete':
          return await _delete(skillsRoot, name, startedAt);
        case 'patch':
          return await _patch(args, skillsRoot, name, startedAt);
        case 'write_file':
          return await _writeFile(args, skillsRoot, name, startedAt);
        case 'remove_file':
          return await _removeFile(args, skillsRoot, name, startedAt);
        default:
          throw StateError('Unsupported validated action: $action');
      }
    } catch (error, stack) {
      return AiToolUtils.invalidResult(
        _toolName,
        '$action failed: $error\n$stack',
      );
    }
  }

  // ──────────────────────────────────────────────────────────────
  // Actions
  // ──────────────────────────────────────────────────────────────

  Future<AiToolExecutionResult> _create(
    Map<String, Object?> args,
    String skillsRoot,
    String name,
    Stopwatch startedAt,
  ) async {
    final category = AiToolUtils.readString(args['category']);
    final content = '${args['content'] ?? ''}';

    if (category.isNotEmpty) {
      final categoryError = _validateCategory(category);
      if (categoryError != null) {
        return AiToolUtils.invalidResult(_toolName, categoryError);
      }
    }
    final sizeError = _validateContentSize(content);
    if (sizeError != null) {
      return AiToolUtils.invalidResult(_toolName, sizeError);
    }
    final frontmatterError = _validateFrontmatter(content);
    if (frontmatterError != null) {
      return AiToolUtils.invalidResult(_toolName, frontmatterError);
    }

    final collisionError = await _checkNameCollision(skillsRoot, name);
    if (collisionError != null) {
      return AiToolUtils.invalidResult(_toolName, collisionError);
    }

    final skillDir = _skillDir(skillsRoot, category, name);
    final skillFile = File(p.join(skillDir, 'SKILL.md'));
    if (await skillFile.exists()) {
      return AiToolUtils.invalidResult(
        _toolName,
        'Skill already exists at $skillDir.',
      );
    }
    await Directory(skillsRoot).create(recursive: true);
    if (!await isPhysicalPathWithinOrEqual(
      skillsRoot,
      skillFile.path,
    ).timeout(_skillScanIdleTimeout, onTimeout: () => false)) {
      return AiToolUtils.invalidResult(
        _toolName,
        'Skill path resolves outside the configured skills directory.',
      );
    }

    await writeFileAtomically(skillFile, content);

    return AiToolUtils.simpleSuccessResult(
      command: 'SkillManager create $name',
      output: 'Created skill $name at ${skillFile.path}',
      durationMs: startedAt.elapsedMilliseconds,
      workingDirectory: skillDir,
      isWriteCommand: true,
      metadata: <String, Object?>{
        'tool_source': 'builtin',
        'skill_action': 'create',
        'skill_name': name,
        if (category.isNotEmpty) 'skill_category': category,
        'skill_path': skillFile.path,
      },
    );
  }

  Future<AiToolExecutionResult> _edit(
    Map<String, Object?> args,
    String skillsRoot,
    String name,
    Stopwatch startedAt,
  ) async {
    final content = '${args['content'] ?? ''}';

    final sizeError = _validateContentSize(content);
    if (sizeError != null) {
      return AiToolUtils.invalidResult(_toolName, sizeError);
    }
    final frontmatterError = _validateFrontmatter(content);
    if (frontmatterError != null) {
      return AiToolUtils.invalidResult(_toolName, frontmatterError);
    }

    final skillContextResult = await _locateSkillContext(skillsRoot, name);
    if (skillContextResult.error != null) {
      return AiToolUtils.invalidResult(_toolName, skillContextResult.error!);
    }
    final skillContext = skillContextResult.context!;

    await writeFileAtomically(skillContext.skillFile, content);

    return AiToolUtils.simpleSuccessResult(
      command: 'SkillManager edit $name',
      output: 'Rewrote SKILL.md at ${skillContext.skillFile.path}',
      durationMs: startedAt.elapsedMilliseconds,
      workingDirectory: skillContext.skillDir.path,
      isWriteCommand: true,
      metadata: <String, Object?>{
        'tool_source': 'builtin',
        'skill_action': 'edit',
        'skill_name': name,
        'skill_path': skillContext.skillFile.path,
      },
    );
  }

  Future<AiToolExecutionResult> _delete(
    String skillsRoot,
    String name,
    Stopwatch startedAt,
  ) async {
    final skillContextResult = await _locateSkillContext(skillsRoot, name);
    if (skillContextResult.error != null) {
      return AiToolUtils.invalidResult(_toolName, skillContextResult.error!);
    }
    final skillContext = skillContextResult.context!;

    final skillDir = skillContext.skillDir;
    if (!isPathWithinOrEqual(skillsRoot, skillDir.path) ||
        p.equals(skillDir.path, skillsRoot)) {
      return AiToolUtils.invalidResult(
        _toolName,
        'Refusing to delete path outside skills directory: ${skillDir.path}.',
      );
    }

    await deletePathBounded(
      p.absolute(skillDir.path),
      policy: _skillDeletePolicy,
      allowMissing: false,
      allowedRoot: p.absolute(skillsRoot),
    );
    await _deleteEmptyAncestorDirs(
      start: skillDir.parent,
      stopAt: Directory(skillsRoot),
      logContext: 'delete empty parent category dir',
    );

    return AiToolUtils.simpleSuccessResult(
      command: 'SkillManager delete $name',
      output: 'Deleted skill $name at ${skillDir.path}',
      durationMs: startedAt.elapsedMilliseconds,
      workingDirectory: skillsRoot,
      isWriteCommand: true,
      metadata: <String, Object?>{
        'tool_source': 'builtin',
        'skill_action': 'delete',
        'skill_name': name,
        'skill_path': skillDir.path,
      },
    );
  }

  Future<AiToolExecutionResult> _patch(
    Map<String, Object?> args,
    String skillsRoot,
    String name,
    Stopwatch startedAt,
  ) async {
    final oldString = '${args['old_string'] ?? ''}';
    final newString = '${args['new_string'] ?? ''}';
    final replaceAll = AiToolUtils.readBool(args['replace_all']) == true;
    final filePathArg = AiToolUtils.readString(args['file_path']);

    if (oldString.isEmpty) {
      return AiToolUtils.invalidResult(
        _toolName,
        'old_string must not be empty.',
      );
    }
    if (oldString == newString) {
      return AiToolUtils.invalidResult(
        _toolName,
        'old_string and new_string must differ.',
      );
    }

    final skillContextResult = await _locateSkillContext(skillsRoot, name);
    if (skillContextResult.error != null) {
      return AiToolUtils.invalidResult(_toolName, skillContextResult.error!);
    }
    final skillContext = skillContextResult.context!;

    final File targetFile;
    final bool patchingSkillMd;
    if (filePathArg.isEmpty) {
      targetFile = skillContext.skillFile;
      patchingSkillMd = true;
    } else {
      final resolved = await _resolveSkillSubFile(skillContext, filePathArg);
      if (resolved.error != null) {
        return AiToolUtils.invalidResult(_toolName, resolved.error!);
      }
      targetFile = resolved.file!;
      patchingSkillMd = false;
      if (!await targetFile.exists()) {
        return AiToolUtils.invalidResult(
          _toolName,
          'file_path "$filePathArg" does not exist in skill "$name".',
        );
      }
    }

    final readResult = await _readPatchTarget(targetFile, patchingSkillMd);
    if (readResult.error != null) {
      return AiToolUtils.invalidResult(_toolName, readResult.error!);
    }
    final original = readResult.content!;
    final occurrences = _countOccurrences(original, oldString);
    if (occurrences == 0) {
      return AiToolUtils.invalidResult(
        _toolName,
        'old_string not found in ${safeRelativePathForDisplay(targetFile.path, from: skillContext.skillDir.path)}.',
      );
    }
    if (occurrences > 1 && !replaceAll) {
      return AiToolUtils.invalidResult(
        _toolName,
        'old_string matches $occurrences occurrences; pass replace_all=true '
        'to replace all, or refine old_string for a unique match.',
      );
    }

    final updated = original.replaceAll(oldString, newString);

    if (patchingSkillMd) {
      final sizeError = _validateContentSize(updated);
      if (sizeError != null) {
        return AiToolUtils.invalidResult(_toolName, sizeError);
      }
      final frontmatterError = _validateFrontmatter(updated);
      if (frontmatterError != null) {
        return AiToolUtils.invalidResult(
          _toolName,
          'patch would break frontmatter: $frontmatterError',
        );
      }
    }

    await writeFileAtomically(targetFile, updated);

    return AiToolUtils.simpleSuccessResult(
      command: 'SkillManager patch $name',
      output:
          'Patched ${targetFile.path} ($occurrences replacement'
          '${occurrences == 1 ? '' : 's'}).',
      durationMs: startedAt.elapsedMilliseconds,
      workingDirectory: skillContext.skillDir.path,
      isWriteCommand: true,
      metadata: <String, Object?>{
        'tool_source': 'builtin',
        'skill_action': 'patch',
        'skill_name': name,
        'skill_path': targetFile.path,
        'replacements': occurrences,
      },
    );
  }

  Future<AiToolExecutionResult> _writeFile(
    Map<String, Object?> args,
    String skillsRoot,
    String name,
    Stopwatch startedAt,
  ) async {
    final content = '${args['content'] ?? ''}';

    final contentSizeError = _validateSidecarContentSize(content);
    if (contentSizeError != null) {
      return AiToolUtils.invalidResult(_toolName, contentSizeError);
    }
    final targetResult = await _locateRequiredSkillSubFile(
      args,
      skillsRoot,
      name,
    );
    if (targetResult.error != null) {
      return AiToolUtils.invalidResult(_toolName, targetResult.error!);
    }

    final skillContext = targetResult.context!;
    final target = targetResult.file!;
    await writeFileAtomically(target, content);

    return AiToolUtils.simpleSuccessResult(
      command: 'SkillManager write_file $name',
      output: 'Wrote ${target.path}',
      durationMs: startedAt.elapsedMilliseconds,
      workingDirectory: skillContext.skillDir.path,
      isWriteCommand: true,
      metadata: <String, Object?>{
        'tool_source': 'builtin',
        'skill_action': 'write_file',
        'skill_name': name,
        'skill_path': target.path,
      },
    );
  }

  Future<AiToolExecutionResult> _removeFile(
    Map<String, Object?> args,
    String skillsRoot,
    String name,
    Stopwatch startedAt,
  ) async {
    final targetResult = await _locateRequiredSkillSubFile(
      args,
      skillsRoot,
      name,
    );
    if (targetResult.error != null) {
      return AiToolUtils.invalidResult(_toolName, targetResult.error!);
    }

    final skillContext = targetResult.context!;
    final target = targetResult.file!;
    if (!await target.exists()) {
      return AiToolUtils.invalidResult(
        _toolName,
        'file_path "${targetResult.relativePath}" does not exist in skill "$name".',
      );
    }
    await target.delete();

    await _deleteEmptyAncestorDirs(
      start: target.parent,
      stopAt: skillContext.skillDir,
      logContext: 'delete empty skill sidecar parent dir',
    );

    return AiToolUtils.simpleSuccessResult(
      command: 'SkillManager remove_file $name',
      output: 'Removed ${target.path}',
      durationMs: startedAt.elapsedMilliseconds,
      workingDirectory: skillContext.skillDir.path,
      isWriteCommand: true,
      metadata: <String, Object?>{
        'tool_source': 'builtin',
        'skill_action': 'remove_file',
        'skill_name': name,
        'skill_path': target.path,
      },
    );
  }

  // ──────────────────────────────────────────────────────────────
  // Helpers
  // ──────────────────────────────────────────────────────────────

  String? _resolveSkillsRoot() {
    final raw = skillsDirProvider().trim();
    if (raw.isEmpty) return null;
    return p.normalize(raw);
  }

  String _skillDir(String skillsRoot, String category, String name) {
    if (category.isEmpty) {
      return p.normalize(p.join(skillsRoot, name));
    }
    return p.normalize(p.join(skillsRoot, category, name));
  }

  Future<String?> _checkNameCollision(String skillsRoot, String name) async {
    final searchResult = await _findSkillFile(skillsRoot, name);
    if (searchResult.error != null) return searchResult.error;
    final file = searchResult.file;
    if (file == null) return null;
    return 'A skill named "$name" already exists at ${file.path}.';
  }

  Future<_SkillContextResult> _locateSkillContext(
    String skillsRoot,
    String name,
  ) async {
    final searchResult = await _findSkillFile(skillsRoot, name);
    if (searchResult.error != null) {
      return _SkillContextResult(error: searchResult.error);
    }
    final skillFile = searchResult.file;
    if (skillFile == null) {
      return _SkillContextResult(
        error: 'Skill "$name" not found under $skillsRoot.',
      );
    }
    final skillDir = skillFile.parent;
    if (!isPathWithinOrEqual(skillsRoot, skillDir.path) ||
        p.equals(p.normalize(skillsRoot), p.normalize(skillDir.path))) {
      return _SkillContextResult(
        error: 'Skill "$name" resolves outside skills directory.',
      );
    }
    return _SkillContextResult(
      context: _SkillFileContext(skillFile: skillFile, skillDir: skillDir),
    );
  }

  Future<_SkillFileSearchResult> _findSkillFile(
    String skillsRoot,
    String name,
  ) async {
    final rootDir = Directory(skillsRoot);
    if (!await rootDir.exists()) return const _SkillFileSearchResult();

    var scanned = 0;
    final stopwatch = Stopwatch()..start();
    try {
      await for (final entity
          in rootDir
              .list(recursive: true, followLinks: false)
              .timeout(_skillScanIdleTimeout)) {
        if (stopwatch.elapsed >= _skillScanTotalTimeout) {
          return _SkillFileSearchResult(
            error: 'Skill scan timed out under $skillsRoot.',
          );
        }
        scanned += 1;
        if (scanned > _maxSkillScanEntities) {
          return _SkillFileSearchResult(
            error:
                'Skill scan exceeded $_maxSkillScanEntities entries under $skillsRoot.',
          );
        }
        if (entity is! File) continue;
        if (p.basename(entity.path) != 'SKILL.md') continue;
        final dirName = p.basename(p.dirname(entity.path));
        if (dirName == name) return _SkillFileSearchResult(file: entity);
      }
    } on TimeoutException {
      return _SkillFileSearchResult(
        error: 'Skill scan timed out under $skillsRoot.',
      );
    } on FileSystemException catch (error) {
      return _SkillFileSearchResult(
        error: 'Unable to scan skills directory $skillsRoot: ${error.message}',
      );
    } finally {
      stopwatch.stop();
    }
    return const _SkillFileSearchResult();
  }

  Future<_SkillSubFileResolution> _resolveSkillSubFile(
    _SkillFileContext skillContext,
    String relativePath,
  ) async {
    final validationError = _validateSkillSubPath(relativePath);
    if (validationError != null) {
      return _SkillSubFileResolution(error: validationError);
    }
    final resolved = p.normalize(
      p.join(skillContext.skillDir.path, relativePath),
    );
    if (!isPathWithinOrEqual(skillContext.skillDir.path, resolved) ||
        p.equals(skillContext.skillDir.path, resolved)) {
      return const _SkillSubFileResolution(
        error: 'file_path must resolve within the skill directory.',
      );
    }
    if (p.equals(resolved, skillContext.skillFile.path)) {
      return const _SkillSubFileResolution(
        error: 'Use edit/patch/delete for SKILL.md.',
      );
    }
    if (!await isPhysicalPathWithinOrEqual(
      skillContext.skillDir.path,
      resolved,
    ).timeout(_skillScanIdleTimeout, onTimeout: () => false)) {
      return const _SkillSubFileResolution(
        error: 'file_path resolves outside the skill directory.',
      );
    }
    return _SkillSubFileResolution(file: File(resolved));
  }

  Future<_SkillSubFileTargetResult> _locateRequiredSkillSubFile(
    Map<String, Object?> args,
    String skillsRoot,
    String name,
  ) async {
    final relativePath = AiToolUtils.readString(args['file_path']);
    if (relativePath.isEmpty) {
      return const _SkillSubFileTargetResult(error: 'file_path is required.');
    }
    final contextResult = await _locateSkillContext(skillsRoot, name);
    if (contextResult.error != null) {
      return _SkillSubFileTargetResult(
        relativePath: relativePath,
        error: contextResult.error,
      );
    }
    final context = contextResult.context!;
    final fileResult = await _resolveSkillSubFile(context, relativePath);
    if (fileResult.error != null) {
      return _SkillSubFileTargetResult(
        relativePath: relativePath,
        error: fileResult.error,
      );
    }
    return _SkillSubFileTargetResult(
      context: context,
      file: fileResult.file,
      relativePath: relativePath,
    );
  }

  /// Validates a sub-path relative to a skill directory. Allowed values are
  /// within `{references, templates, scripts, assets}/...` and must not
  /// traverse outside via `..`.
  String? _validateSkillSubPath(String relativePath) {
    final pathError = safeRelativePathError(relativePath);
    if (pathError != null) {
      return 'file_path $pathError';
    }
    final normalized = p.normalize(relativePath.trim());
    final segments = p.split(normalized);
    final head = segments.first;
    if (!_allowedWriteSubdirs.contains(head)) {
      return 'file_path first segment must be one of '
          '${_allowedWriteSubdirs.join(', ')}; got "$head".';
    }
    if (segments.length < 2) {
      return 'file_path must point to a file inside $head/, not the directory itself.';
    }
    return null;
  }

  Future<_TextFileReadResult> _readPatchTarget(
    File file,
    bool isSkillManifest,
  ) async {
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file &&
        stat.type != FileSystemEntityType.link) {
      return _TextFileReadResult(error: 'Target is not a file: ${file.path}');
    }
    final maxBytes = isSkillManifest
        ? maxSkillContentLength * 4
        : _maxSidecarContentLength;
    if (stat.size > maxBytes) {
      return _TextFileReadResult(
        error:
            'Target file is too large to patch safely '
            '(${stat.size} bytes, limit $maxBytes).',
      );
    }
    try {
      return _TextFileReadResult(
        content: await readBoundedFileString(file, maxBytes: maxBytes),
      );
    } on IOException catch (error) {
      return _TextFileReadResult(error: 'Unable to read ${file.path}: $error');
    } on FormatException catch (error) {
      return _TextFileReadResult(
        error: 'Unable to decode ${file.path}: $error',
      );
    }
  }

  Future<void> _deleteEmptyAncestorDirs({
    required Directory start,
    required Directory stopAt,
    required String logContext,
  }) async {
    await deleteEmptyAncestorDirectories(
      start: start,
      stopAt: stopAt,
      continuePastMissing: false,
      onError: (directory, error, stack) {
        silentLog('ai_skill_manager_tool', logContext, error, stack);
      },
    );
  }

  int _countOccurrences(String haystack, String needle) {
    if (needle.isEmpty) return 0;
    var count = 0;
    var index = 0;
    while (true) {
      final found = haystack.indexOf(needle, index);
      if (found < 0) break;
      count++;
      index = found + needle.length;
    }
    return count;
  }

  String? _validateName(String name) {
    if (name.isEmpty) return 'name is required.';
    if (name.length > _maxNameLength) {
      return 'name must be at most $_maxNameLength characters.';
    }
    if (!_nameRegex.hasMatch(name)) {
      return 'name must match ${_nameRegex.pattern} (lowercase alphanumerics, dot, underscore, hyphen).';
    }
    return null;
  }

  String? _validateCategory(String category) {
    if (category.length > _maxNameLength) {
      return 'category must be at most $_maxNameLength characters.';
    }
    final segments = p.split(category);
    if (segments.length != 1 || segments.first != category) {
      return 'category must be a single path segment.';
    }
    if (!_nameRegex.hasMatch(category)) {
      return 'category must match ${_nameRegex.pattern}.';
    }
    return null;
  }

  String? _validateContentSize(String content) {
    if (content.length > maxSkillContentLength) {
      return 'SKILL.md content exceeds the maximum allowed size '
          '(${content.length} chars, limit $maxSkillContentLength).';
    }
    return null;
  }

  String? _validateSidecarContentSize(String content) {
    if (content.length > _maxSidecarContentLength) {
      return 'file content exceeds the maximum allowed size '
          '(${content.length} chars, limit $_maxSidecarContentLength).';
    }
    return null;
  }

  /// Returns `null` when the content has valid frontmatter; otherwise returns
  /// an error message.
  String? _validateFrontmatter(String content) {
    if (!content.startsWith('---\n')) {
      return 'content must begin with a YAML frontmatter block delimited by "---".';
    }
    final closingIndex = content.indexOf('\n---\n', 4);
    if (closingIndex < 0) {
      return 'frontmatter closing "---" line not found.';
    }
    final frontmatterText = content.substring(4, closingIndex);
    final body = content.substring(closingIndex + 5);
    if (body.trim().isEmpty) {
      return 'skill body (content after frontmatter) must not be empty.';
    }
    final dynamic parsed;
    try {
      parsed = loadYaml(frontmatterText);
    } catch (error) {
      return 'frontmatter is not valid YAML: $error';
    }
    if (parsed is! Map) {
      return 'frontmatter must be a YAML mapping.';
    }
    final nameValue = parsed['name'];
    if (nameValue == null || '$nameValue'.trim().isEmpty) {
      return 'frontmatter must include a non-empty "name" field.';
    }
    final descriptionValue = parsed['description'];
    if (descriptionValue == null || '$descriptionValue'.trim().isEmpty) {
      return 'frontmatter must include a non-empty "description" field.';
    }
    if ('$descriptionValue'.length > _maxDescriptionLength) {
      return 'frontmatter "description" must be at most $_maxDescriptionLength characters.';
    }
    return null;
  }
}

class _SkillFileContext {
  const _SkillFileContext({required this.skillFile, required this.skillDir});

  final File skillFile;
  final Directory skillDir;
}

class _SkillContextResult {
  const _SkillContextResult({this.context, this.error});

  final _SkillFileContext? context;
  final String? error;
}

class _SkillFileSearchResult {
  const _SkillFileSearchResult({this.file, this.error});

  final File? file;
  final String? error;
}

class _SkillSubFileResolution {
  const _SkillSubFileResolution({this.file, this.error});

  final File? file;
  final String? error;
}

class _SkillSubFileTargetResult {
  const _SkillSubFileTargetResult({
    this.context,
    this.file,
    this.relativePath = '',
    this.error,
  });

  final _SkillFileContext? context;
  final File? file;
  final String relativePath;
  final String? error;
}

class _TextFileReadResult {
  const _TextFileReadResult({this.content, this.error});

  final String? content;
  final String? error;
}

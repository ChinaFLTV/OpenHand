import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../../../app/support/silent_log.dart';
import '../service/runtime/ai_tool_runtime_service.dart';
import 'ai_tool.dart';
import 'ai_tool_execution_context.dart';
import 'ai_tool_utils.dart';

/// 2026-04-25 SkillManager tool — manages AI skills on disk.
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

  /// Package-private entry point used by tests to exercise the core logic
  /// without needing to construct a full [AiToolExecutionContext].
  Future<AiToolExecutionResult> run(Map<String, Object?> args) async {
    final startedAt = Stopwatch()..start();
    final action = '${args['action'] ?? ''}'.trim();
    if (action.isEmpty) {
      return AiToolUtils.invalidResult(
        _toolName,
        'action is required (one of: create, edit, delete, patch, write_file, remove_file).',
      );
    }

    final skillsRoot = _resolveSkillsRoot();
    if (skillsRoot == null) {
      return AiToolUtils.invalidResult(
        _toolName,
        'skills directory is not configured.',
      );
    }

    try {
      switch (action) {
        case 'create':
          return await _create(args, skillsRoot, startedAt);
        case 'edit':
          return await _edit(args, skillsRoot, startedAt);
        case 'delete':
          return await _delete(args, skillsRoot, startedAt);
        case 'patch':
          return await _patch(args, skillsRoot, startedAt);
        case 'write_file':
          return await _writeFile(args, skillsRoot, startedAt);
        case 'remove_file':
          return await _removeFile(args, skillsRoot, startedAt);
        default:
          return AiToolUtils.invalidResult(
            _toolName,
            'Unknown action: $action.',
          );
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
    Stopwatch startedAt,
  ) async {
    final name = '${args['name'] ?? ''}'.trim();
    final category = '${args['category'] ?? ''}'.trim();
    final content = '${args['content'] ?? ''}';

    final nameError = _validateName(name);
    if (nameError != null) {
      return AiToolUtils.invalidResult(_toolName, nameError);
    }
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

    await Directory(skillDir).create(recursive: true);
    await _atomicWriteString(skillFile, content);

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
    Stopwatch startedAt,
  ) async {
    final name = '${args['name'] ?? ''}'.trim();
    final content = '${args['content'] ?? ''}';

    final nameError = _validateName(name);
    if (nameError != null) {
      return AiToolUtils.invalidResult(_toolName, nameError);
    }
    final sizeError = _validateContentSize(content);
    if (sizeError != null) {
      return AiToolUtils.invalidResult(_toolName, sizeError);
    }
    final frontmatterError = _validateFrontmatter(content);
    if (frontmatterError != null) {
      return AiToolUtils.invalidResult(_toolName, frontmatterError);
    }

    final skillFile = await _locateSkillFile(skillsRoot, name);
    if (skillFile == null) {
      return AiToolUtils.invalidResult(
        _toolName,
        'Skill "$name" not found under $skillsRoot.',
      );
    }

    await _atomicWriteString(skillFile, content);

    return AiToolUtils.simpleSuccessResult(
      command: 'SkillManager edit $name',
      output: 'Rewrote SKILL.md at ${skillFile.path}',
      durationMs: startedAt.elapsedMilliseconds,
      workingDirectory: skillFile.parent.path,
      isWriteCommand: true,
      metadata: <String, Object?>{
        'tool_source': 'builtin',
        'skill_action': 'edit',
        'skill_name': name,
        'skill_path': skillFile.path,
      },
    );
  }

  Future<AiToolExecutionResult> _delete(
    Map<String, Object?> args,
    String skillsRoot,
    Stopwatch startedAt,
  ) async {
    final name = '${args['name'] ?? ''}'.trim();
    final nameError = _validateName(name);
    if (nameError != null) {
      return AiToolUtils.invalidResult(_toolName, nameError);
    }

    final skillFile = await _locateSkillFile(skillsRoot, name);
    if (skillFile == null) {
      return AiToolUtils.invalidResult(
        _toolName,
        'Skill "$name" not found under $skillsRoot.',
      );
    }

    final skillDir = skillFile.parent;
    if (!_isWithinOrEqual(skillsRoot, skillDir.path) ||
        p.equals(skillDir.path, skillsRoot)) {
      return AiToolUtils.invalidResult(
        _toolName,
        'Refusing to delete path outside skills directory: ${skillDir.path}.',
      );
    }

    await skillDir.delete(recursive: true);
    // Clean up empty category parent, if applicable.
    final parent = skillDir.parent;
    if (!p.equals(parent.path, skillsRoot) &&
        _isWithinOrEqual(skillsRoot, parent.path) &&
        await _isDirEmpty(parent)) {
      try {
        await parent.delete();
      } catch (error, stack) {
        silentLog('ai_skill_manager_tool', 'delete empty parent category dir', error, stack);
      }
    }

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
    Stopwatch startedAt,
  ) async {
    final name = '${args['name'] ?? ''}'.trim();
    final oldString = '${args['old_string'] ?? ''}';
    final newString = '${args['new_string'] ?? ''}';
    final replaceAll = args['replace_all'] == true;
    final filePathArg = '${args['file_path'] ?? ''}'.trim();

    final nameError = _validateName(name);
    if (nameError != null) {
      return AiToolUtils.invalidResult(_toolName, nameError);
    }
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

    final skillFile = await _locateSkillFile(skillsRoot, name);
    if (skillFile == null) {
      return AiToolUtils.invalidResult(
        _toolName,
        'Skill "$name" not found under $skillsRoot.',
      );
    }
    final skillDir = skillFile.parent.path;

    final File targetFile;
    final bool patchingSkillMd;
    if (filePathArg.isEmpty) {
      targetFile = skillFile;
      patchingSkillMd = true;
    } else {
      final subPathError = _validateSkillSubPath(filePathArg);
      if (subPathError != null) {
        return AiToolUtils.invalidResult(_toolName, subPathError);
      }
      final resolved = p.normalize(p.join(skillDir, filePathArg));
      if (!_isWithinOrEqual(skillDir, resolved) ||
          p.equals(skillDir, resolved)) {
        return AiToolUtils.invalidResult(
          _toolName,
          'file_path must resolve within the skill directory.',
        );
      }
      targetFile = File(resolved);
      patchingSkillMd = p.equals(resolved, skillFile.path);
      if (!await targetFile.exists()) {
        return AiToolUtils.invalidResult(
          _toolName,
          'file_path "$filePathArg" does not exist in skill "$name".',
        );
      }
    }

    final original = await targetFile.readAsString();
    final occurrences = _countOccurrences(original, oldString);
    if (occurrences == 0) {
      return AiToolUtils.invalidResult(
        _toolName,
        'old_string not found in ${p.relative(targetFile.path, from: skillDir)}.',
      );
    }
    if (occurrences > 1 && !replaceAll) {
      return AiToolUtils.invalidResult(
        _toolName,
        'old_string matches $occurrences occurrences; pass replace_all=true '
        'to replace all, or refine old_string for a unique match.',
      );
    }

    final String updated;
    if (replaceAll || occurrences == 1) {
      updated = original.replaceAll(oldString, newString);
    } else {
      // Unreachable; above branch covers single-match replace without
      // `replace_all`.
      updated = original;
    }

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

    await _atomicWriteString(targetFile, updated);

    return AiToolUtils.simpleSuccessResult(
      command: 'SkillManager patch $name',
      output:
          'Patched ${targetFile.path} ($occurrences replacement'
          '${occurrences == 1 ? '' : 's'}).',
      durationMs: startedAt.elapsedMilliseconds,
      workingDirectory: skillDir,
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
    Stopwatch startedAt,
  ) async {
    final name = '${args['name'] ?? ''}'.trim();
    final filePathArg = '${args['file_path'] ?? ''}'.trim();
    final content = '${args['content'] ?? ''}';

    final nameError = _validateName(name);
    if (nameError != null) {
      return AiToolUtils.invalidResult(_toolName, nameError);
    }
    if (filePathArg.isEmpty) {
      return AiToolUtils.invalidResult(_toolName, 'file_path is required.');
    }
    final subPathError = _validateSkillSubPath(filePathArg);
    if (subPathError != null) {
      return AiToolUtils.invalidResult(_toolName, subPathError);
    }

    final skillFile = await _locateSkillFile(skillsRoot, name);
    if (skillFile == null) {
      return AiToolUtils.invalidResult(
        _toolName,
        'Skill "$name" not found under $skillsRoot.',
      );
    }
    final skillDir = skillFile.parent.path;
    final resolved = p.normalize(p.join(skillDir, filePathArg));
    if (!_isWithinOrEqual(skillDir, resolved) || p.equals(skillDir, resolved)) {
      return AiToolUtils.invalidResult(
        _toolName,
        'file_path must resolve within the skill directory.',
      );
    }
    if (p.equals(resolved, skillFile.path)) {
      return AiToolUtils.invalidResult(
        _toolName,
        'Use edit/patch instead of write_file for SKILL.md.',
      );
    }

    final target = File(resolved);
    await target.parent.create(recursive: true);
    await _atomicWriteString(target, content);

    return AiToolUtils.simpleSuccessResult(
      command: 'SkillManager write_file $name',
      output: 'Wrote ${target.path}',
      durationMs: startedAt.elapsedMilliseconds,
      workingDirectory: skillDir,
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
    Stopwatch startedAt,
  ) async {
    final name = '${args['name'] ?? ''}'.trim();
    final filePathArg = '${args['file_path'] ?? ''}'.trim();

    final nameError = _validateName(name);
    if (nameError != null) {
      return AiToolUtils.invalidResult(_toolName, nameError);
    }
    if (filePathArg.isEmpty) {
      return AiToolUtils.invalidResult(_toolName, 'file_path is required.');
    }
    final subPathError = _validateSkillSubPath(filePathArg);
    if (subPathError != null) {
      return AiToolUtils.invalidResult(_toolName, subPathError);
    }

    final skillFile = await _locateSkillFile(skillsRoot, name);
    if (skillFile == null) {
      return AiToolUtils.invalidResult(
        _toolName,
        'Skill "$name" not found under $skillsRoot.',
      );
    }
    final skillDir = skillFile.parent.path;
    final resolved = p.normalize(p.join(skillDir, filePathArg));
    if (!_isWithinOrEqual(skillDir, resolved) || p.equals(skillDir, resolved)) {
      return AiToolUtils.invalidResult(
        _toolName,
        'file_path must resolve within the skill directory.',
      );
    }
    if (p.equals(resolved, skillFile.path)) {
      return AiToolUtils.invalidResult(
        _toolName,
        'Refusing to remove SKILL.md; use delete to remove the whole skill.',
      );
    }

    final target = File(resolved);
    if (!await target.exists()) {
      return AiToolUtils.invalidResult(
        _toolName,
        'file_path "$filePathArg" does not exist in skill "$name".',
      );
    }
    await target.delete();

    // Clean up empty parent dirs up to (but never including) skillDir.
    Directory cursor = target.parent;
    while (!p.equals(cursor.path, skillDir) &&
        _isWithinOrEqual(skillDir, cursor.path) &&
        await _isDirEmpty(cursor)) {
      try {
        await cursor.delete();
      } catch (_) {
        break;
      }
      cursor = cursor.parent;
    }

    return AiToolUtils.simpleSuccessResult(
      command: 'SkillManager remove_file $name',
      output: 'Removed ${target.path}',
      durationMs: startedAt.elapsedMilliseconds,
      workingDirectory: skillDir,
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
    final rootDir = Directory(skillsRoot);
    if (!await rootDir.exists()) return null;
    await for (final entity in rootDir.list(recursive: true)) {
      if (entity is! File) continue;
      if (p.basename(entity.path) != 'SKILL.md') continue;
      final dirName = p.basename(p.dirname(entity.path));
      if (dirName == name) {
        return 'A skill named "$name" already exists at ${entity.path}.';
      }
    }
    return null;
  }

  /// Locates the SKILL.md file for a skill named [name] anywhere under
  /// [skillsRoot]. Returns null if not found.
  Future<File?> _locateSkillFile(String skillsRoot, String name) async {
    final rootDir = Directory(skillsRoot);
    if (!await rootDir.exists()) return null;
    await for (final entity in rootDir.list(recursive: true)) {
      if (entity is! File) continue;
      if (p.basename(entity.path) != 'SKILL.md') continue;
      final dirName = p.basename(p.dirname(entity.path));
      if (dirName == name) return entity;
    }
    return null;
  }

  bool _isWithinOrEqual(String parent, String child) {
    final np = p.normalize(parent);
    final nc = p.normalize(child);
    return p.equals(np, nc) || p.isWithin(np, nc);
  }

  Future<bool> _isDirEmpty(Directory dir) async {
    if (!await dir.exists()) return false;
    await for (final _ in dir.list()) {
      return false;
    }
    return true;
  }

  /// Validates a sub-path relative to a skill directory. Allowed values are
  /// within `{references, templates, scripts, assets}/...` and must not
  /// traverse outside via `..`.
  String? _validateSkillSubPath(String relativePath) {
    final normalized = p.normalize(relativePath);
    if (p.isAbsolute(normalized)) {
      return 'file_path must be a relative path within the skill directory.';
    }
    final segments = p.split(normalized);
    if (segments.isEmpty) {
      return 'file_path must not be empty.';
    }
    if (segments.contains('..')) {
      return 'file_path must not traverse parent directories.';
    }
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

  /// Writes [content] to [file] atomically via a same-directory temp file
  /// plus `rename`.
  Future<void> _atomicWriteString(File file, String content) async {
    await file.parent.create(recursive: true);
    final random = Random().nextInt(1 << 32).toRadixString(16);
    final temp = File(
      p.join(
        file.parent.path,
        '.tmp_${DateTime.now().microsecondsSinceEpoch}_$random',
      ),
    );
    try {
      await temp.writeAsString(content, flush: true);
      await temp.rename(file.path);
    } catch (error) {
      if (await temp.exists()) {
        try {
          await temp.delete();
        } catch (cleanupError, cleanupStack) {
          silentLog('ai_skill_manager_tool', 'cleanup temp file after failed atomic write', cleanupError, cleanupStack);
        }
      }
      rethrow;
    }
  }
}

import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../service/ai_tool_runtime_service.dart';
import 'ai_tool.dart';
import 'ai_tool_execution_context.dart';
import 'ai_tool_utils.dart';

/// 2026-04-25 SkillManager tool — manages AI skills on disk.
///
/// Supports the following actions (specified via `args['action']`):
/// - `create`   : create a new skill directory with SKILL.md
///
/// Layout: `<skillsDir>/[<category>/]<name>/SKILL.md`.
class AiSkillManagerTool extends AiTool {
  AiSkillManagerTool({required this.skillsDirProvider});

  final String Function() skillsDirProvider;

  static const String _toolName = 'SkillManager';
  static const int _maxNameLength = 64;
  static const int _maxDescriptionLength = 1024;
  static const int _maxSkillContentLength = 100000;
  static final RegExp _nameRegex = RegExp(r'^[a-z0-9][a-z0-9._-]*$');

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

  Future<AiToolExecutionResult> _create(
    Map<String, Object?> args,
    String skillsRoot,
    Stopwatch startedAt,
  ) async {
    final name = '${args['name'] ?? ''}'.trim();
    final category = '${args['category'] ?? ''}'.trim();
    final content = '${args['content'] ?? ''}';

    final nameError = _validateName(name);
    if (nameError != null) return AiToolUtils.invalidResult(_toolName, nameError);
    if (category.isNotEmpty) {
      final categoryError = _validateCategory(category);
      if (categoryError != null) return AiToolUtils.invalidResult(_toolName, categoryError);
    }
    final sizeError = _validateContentSize(content);
    if (sizeError != null) return AiToolUtils.invalidResult(_toolName, sizeError);
    final frontmatterError = _validateFrontmatter(content);
    if (frontmatterError != null) return AiToolUtils.invalidResult(_toolName, frontmatterError);

    final collisionError = await _checkNameCollision(skillsRoot, name);
    if (collisionError != null) return AiToolUtils.invalidResult(_toolName, collisionError);

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
    if (content.length > _maxSkillContentLength) {
      return 'SKILL.md content exceeds the maximum allowed size '
          '(${content.length} chars, limit $_maxSkillContentLength).';
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
    final temp = File(p.join(
      file.parent.path,
      '.tmp_${DateTime.now().microsecondsSinceEpoch}_$random',
    ));
    try {
      await temp.writeAsString(content, flush: true);
      await temp.rename(file.path);
    } catch (error) {
      if (await temp.exists()) {
        try {
          await temp.delete();
        } catch (_) {}
      }
      rethrow;
    }
  }
}

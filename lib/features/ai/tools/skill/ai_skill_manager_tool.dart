import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../../../../app/support/silent_log.dart';
import '../../../../shared/db/atomic_file_operations.dart';
import '../../../../shared/util/bounded_delete.dart';
import '../../../../shared/util/bounded_file_io.dart';
import '../../../../shared/util/byte_size_format.dart';
import '../../../../shared/util/directory_cleanup.dart';
import '../../../../shared/util/path_safety.dart';
import '../../../../shared/util/physical_path_safety.dart';
import '../../service/runtime/ai_tool_runtime_service.dart';
import '../ai_tool.dart';
import '../ai_tool_execution_context.dart';
import '../ai_tool_utils.dart';

/// 管理磁盘上的 AI 技能，支持创建、编辑、删除、补丁和旁路文件操作。
/// 目录结构：`<skillsDir>/[<category>/]<name>/SKILL.md`。
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
  static const int _maxSidecarContentLength = 2 * kBytesPerMiB;
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

  /// 此工具支持删除操作。
  @override
  bool get isDestructive => true;

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    return run(context.decodedArguments);
  }

  /// 供已解析参数的调用方直接执行。
  Future<AiToolExecutionResult> run(Map<String, Object?> args) async {
    final startedAt = Stopwatch()..start();
    final action = AiToolUtils.readString(args['action']);
    if (action.isEmpty) {
      return AiToolUtils.invalidResult(
        _toolName,
        '必须提供 action，可选值：${_supportedActions.join(', ')}。',
      );
    }

    final skillsRoot = _resolveSkillsRoot();
    if (skillsRoot == null) {
      return AiToolUtils.invalidResult(_toolName, '未配置技能目录。');
    }
    if (!_supportedActions.contains(action)) {
      return AiToolUtils.invalidResult(_toolName, '未知 action：$action。');
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
          throw StateError('不支持已校验的 action：$action');
      }
    } catch (error, stack) {
      silentLog('ai_skill_manager_tool', '执行技能操作 $action', error, stack);
      return AiToolUtils.invalidResult(_toolName, '$action 执行失败：$error');
    }
  }

  // 操作实现

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
    if (await AiToolUtils.fileExistsBounded(skillFile)) {
      return AiToolUtils.invalidResult(_toolName, '技能已存在：$skillDir。');
    }
    await Directory(
      skillsRoot,
    ).create(recursive: true).timeout(_skillScanIdleTimeout);
    if (!await isPhysicalPathWithinOrEqual(
      skillsRoot,
      skillFile.path,
    ).timeout(_skillScanIdleTimeout, onTimeout: () => false)) {
      return AiToolUtils.invalidResult(_toolName, '技能路径解析到已配置技能目录之外。');
    }

    await writeFileAtomically(skillFile, content);

    return AiToolUtils.simpleSuccessResult(
      command: 'SkillManager create $name',
      output: '已在 ${skillFile.path} 创建技能 $name。',
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
      output: '已重写 ${skillContext.skillFile.path}。',
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
        '拒绝删除技能目录之外的路径：${skillDir.path}。',
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
      logContext: '删除空的父级分类目录',
    );

    return AiToolUtils.simpleSuccessResult(
      command: 'SkillManager delete $name',
      output: '已删除 ${skillDir.path} 中的技能 $name。',
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
      return AiToolUtils.invalidResult(_toolName, 'old_string 不能为空。');
    }
    if (oldString == newString) {
      return AiToolUtils.invalidResult(
        _toolName,
        'old_string 和 new_string 必须不同。',
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
      if (!await AiToolUtils.fileExistsBounded(targetFile)) {
        return AiToolUtils.invalidResult(
          _toolName,
          '技能“$name”中不存在 file_path“$filePathArg”。',
        );
      }
    }

    final readResult = await _readPatchTarget(targetFile, patchingSkillMd);
    if (readResult.error != null) {
      return AiToolUtils.invalidResult(_toolName, readResult.error!);
    }
    final original = readResult.content!;
    final replacement = AiToolUtils.replaceOnceOrAll(
      content: original,
      oldString: oldString,
      newString: newString,
      replaceAll: replaceAll,
    );
    if (!replacement.success) {
      final relativePath = safeRelativePathForDisplay(
        targetFile.path,
        from: skillContext.skillDir.path,
      );
      return AiToolUtils.invalidResult(
        _toolName,
        '${replacement.errorMessage} ($relativePath)',
      );
    }
    final updated = replacement.content;

    if (patchingSkillMd) {
      final sizeError = _validateContentSize(updated);
      if (sizeError != null) {
        return AiToolUtils.invalidResult(_toolName, sizeError);
      }
      final frontmatterError = _validateFrontmatter(updated);
      if (frontmatterError != null) {
        return AiToolUtils.invalidResult(
          _toolName,
          '补丁会破坏 frontmatter：$frontmatterError',
        );
      }
    }

    await writeFileAtomically(targetFile, updated);

    return AiToolUtils.simpleSuccessResult(
      command: 'SkillManager patch $name',
      output: '已补丁 ${targetFile.path}，替换 ${replacement.replacementCount} 处。',
      durationMs: startedAt.elapsedMilliseconds,
      workingDirectory: skillContext.skillDir.path,
      isWriteCommand: true,
      metadata: <String, Object?>{
        'tool_source': 'builtin',
        'skill_action': 'patch',
        'skill_name': name,
        'skill_path': targetFile.path,
        'replacements': replacement.replacementCount,
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
      output: '已写入 ${target.path}。',
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
    if (!await AiToolUtils.fileExistsBounded(target)) {
      return AiToolUtils.invalidResult(
        _toolName,
        '技能“$name”中不存在 file_path“${targetResult.relativePath}”。',
      );
    }
    await deleteFileAtomically(target);

    await _deleteEmptyAncestorDirs(
      start: target.parent,
      stopAt: skillContext.skillDir,
      logContext: '删除空的技能旁路文件父目录',
    );

    return AiToolUtils.simpleSuccessResult(
      command: 'SkillManager remove_file $name',
      output: '已删除 ${target.path}。',
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
    return '名为“$name”的技能已存在：${file.path}。';
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
      return _SkillContextResult(error: '在 $skillsRoot 下找不到技能“$name”。');
    }
    final skillDir = skillFile.parent;
    if (!isPathWithinOrEqual(skillsRoot, skillDir.path) ||
        p.equals(p.normalize(skillsRoot), p.normalize(skillDir.path))) {
      return _SkillContextResult(error: '技能“$name”的路径解析到技能目录之外。');
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
    if (!await rootDir.exists().timeout(_skillScanIdleTimeout)) {
      return const _SkillFileSearchResult();
    }

    var scanned = 0;
    final stopwatch = Stopwatch()..start();
    try {
      await for (final entity
          in rootDir
              .list(recursive: true, followLinks: false)
              .timeout(_skillScanIdleTimeout)) {
        if (stopwatch.elapsed >= _skillScanTotalTimeout) {
          return _SkillFileSearchResult(error: '扫描技能目录超时：$skillsRoot。');
        }
        scanned += 1;
        if (scanned > _maxSkillScanEntities) {
          return _SkillFileSearchResult(
            error: '扫描 $skillsRoot 时超过 $_maxSkillScanEntities 项上限。',
          );
        }
        if (entity is! File) continue;
        if (p.basename(entity.path) != 'SKILL.md') continue;
        final dirName = p.basename(p.dirname(entity.path));
        if (dirName == name) return _SkillFileSearchResult(file: entity);
      }
    } on TimeoutException {
      return _SkillFileSearchResult(error: '扫描技能目录超时：$skillsRoot。');
    } on FileSystemException catch (error) {
      return _SkillFileSearchResult(
        error: '无法扫描技能目录 $skillsRoot：${error.message}',
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
      return const _SkillSubFileResolution(error: 'file_path 必须解析到技能目录内。');
    }
    if (p.equals(resolved, skillContext.skillFile.path)) {
      return const _SkillSubFileResolution(
        error: '请使用 edit、patch 或 delete 操作 SKILL.md。',
      );
    }
    if (!await isPhysicalPathWithinOrEqual(
      skillContext.skillDir.path,
      resolved,
    ).timeout(_skillScanIdleTimeout, onTimeout: () => false)) {
      return const _SkillSubFileResolution(error: 'file_path 解析到技能目录之外。');
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
      return const _SkillSubFileTargetResult(error: '必须提供 file_path。');
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

  /// 校验技能目录内的相对路径，仅允许写入白名单子目录且禁止向上遍历。
  String? _validateSkillSubPath(String relativePath) {
    final pathError = safeRelativePathError(relativePath);
    if (pathError != null) {
      return 'file_path：$pathError';
    }
    final normalized = p.normalize(relativePath.trim());
    final segments = p.split(normalized);
    final head = segments.first;
    if (!_allowedWriteSubdirs.contains(head)) {
      return 'file_path 首段必须为 ${_allowedWriteSubdirs.join(', ')} 之一，实际为“$head”。';
    }
    if (segments.length < 2) {
      return 'file_path 必须指向 $head/ 内的文件，不能指向目录本身。';
    }
    return null;
  }

  Future<_TextFileReadResult> _readPatchTarget(
    File file,
    bool isSkillManifest,
  ) async {
    final stat = await AiToolUtils.fileStatBounded(file);
    if (stat.type != FileSystemEntityType.file &&
        stat.type != FileSystemEntityType.link) {
      return _TextFileReadResult(error: '目标不是文件：${file.path}');
    }
    final maxBytes = isSkillManifest
        ? maxSkillContentLength * 4
        : _maxSidecarContentLength;
    if (stat.size > maxBytes) {
      return _TextFileReadResult(
        error: '目标文件过大，无法安全应用补丁（${stat.size} 字节，上限 $maxBytes）。',
      );
    }
    try {
      return _TextFileReadResult(
        content: await readBoundedFileString(file, maxBytes: maxBytes),
      );
    } on IOException catch (error) {
      return _TextFileReadResult(error: '无法读取 ${file.path}：$error');
    } on FormatException catch (error) {
      return _TextFileReadResult(error: '无法解码 ${file.path}：$error');
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

  String? _validateName(String name) {
    if (name.isEmpty) return '必须提供 name。';
    if (name.length > _maxNameLength) {
      return 'name 最多为 $_maxNameLength 个字符。';
    }
    if (!_nameRegex.hasMatch(name)) {
      return 'name 必须匹配 ${_nameRegex.pattern}，仅允许小写字母、数字、点、下划线和连字符。';
    }
    return null;
  }

  String? _validateCategory(String category) {
    if (category.length > _maxNameLength) {
      return 'category 最多为 $_maxNameLength 个字符。';
    }
    final segments = p.split(category);
    if (segments.length != 1 || segments.first != category) {
      return 'category 必须为单个路径段。';
    }
    if (!_nameRegex.hasMatch(category)) {
      return 'category 必须匹配 ${_nameRegex.pattern}。';
    }
    return null;
  }

  String? _validateContentSize(String content) {
    if (content.length > maxSkillContentLength) {
      return 'SKILL.md 内容超过允许上限（${content.length} 个字符，上限 $maxSkillContentLength）。';
    }
    return null;
  }

  String? _validateSidecarContentSize(String content) {
    if (content.length > _maxSidecarContentLength) {
      return '文件内容超过允许上限（${content.length} 个字符，上限 $_maxSidecarContentLength）。';
    }
    return null;
  }

  /// frontmatter 有效时返回 null，否则返回错误文案。
  String? _validateFrontmatter(String content) {
    if (!content.startsWith('---\n')) {
      return 'content 必须以“---”分隔的 YAML frontmatter 开头。';
    }
    final closingIndex = content.indexOf('\n---\n', 4);
    if (closingIndex < 0) {
      return '找不到 frontmatter 结束行“---”。';
    }
    final frontmatterText = content.substring(4, closingIndex);
    final body = content.substring(closingIndex + 5);
    if (body.trim().isEmpty) {
      return '技能正文（frontmatter 之后的内容）不能为空。';
    }
    final dynamic parsed;
    try {
      parsed = loadYaml(frontmatterText);
    } catch (error) {
      return 'frontmatter 不是有效 YAML：$error';
    }
    if (parsed is! Map) {
      return 'frontmatter 必须为 YAML 映射。';
    }
    final nameValue = parsed['name'];
    if (nameValue == null || '$nameValue'.trim().isEmpty) {
      return 'frontmatter 必须包含非空 name 字段。';
    }
    final descriptionValue = parsed['description'];
    if (descriptionValue == null || '$descriptionValue'.trim().isEmpty) {
      return 'frontmatter 必须包含非空 description 字段。';
    }
    if ('$descriptionValue'.length > _maxDescriptionLength) {
      return 'frontmatter 的 description 最多为 $_maxDescriptionLength 个字符。';
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

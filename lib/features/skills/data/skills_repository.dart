import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:characters/characters.dart';
import 'package:flutter/foundation.dart';
import 'package:openhand/shared/util/text_normalization.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../../../app/support/openhand_paths.dart';
import '../../../app/support/silent_log.dart';
import '../../../shared/db/atomic_file_operations.dart';
import '../../../shared/util/bounded_copy.dart';
import '../../../shared/util/bounded_delete.dart';
import '../../../shared/util/bounded_directory_io.dart';
import '../../../shared/util/bounded_file_io.dart';
import '../../../shared/util/bounded_zip_archive.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/directory_cleanup.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/path_safety.dart';
import '../../../shared/util/xml_escape.dart';
import '../model/local_skill.dart';

class SkillsRepository {
  static const String _manifestFileName = 'SKILL.md';
  static const String _defaultSkillSlug = 'new-skill';
  static const String _defaultTemplateDescription =
      'Describe what this skill does.';
  static const String _defaultTemplateIcon = '🧩';
  static const String _openAiMetadataRelativePath = 'agents/openai.yaml';
  static const String _openAiAssetsRelativePath = 'agents/assets';
  static const String _generatedEmojiIconFileName = 'skill-icon.svg';
  static const String _generatedImageIconFileName = 'skill-icon.png';
  static const int _maxArchiveEntries = 2000;
  static const int _maxArchivePathCharacters = 4096;
  static const int _maxExtractedArchiveBytes = 160 * kBytesPerMiB;
  static const int _maxInstalledSkillScanEntries = 20000;
  static const int _maxSkillScanDepth = 32;
  static const Duration _skillScanIdleTimeout = Duration(seconds: 3);
  static const Duration _skillScanTotalTimeout = Duration(seconds: 20);
  static const int _maxMetadataBytes = 512 * kBytesPerKiB;
  static const int _maxOptionalAssetBytes = 32 * kBytesPerMiB;
  static const BoundedCopyPolicy _directoryImportCopyPolicy = BoundedCopyPolicy(
    maxEntries: _maxArchiveEntries,
    maxBytes: _maxExtractedArchiveBytes,
    maxDepth: _maxSkillScanDepth,
    totalTimeout: Duration(minutes: 1),
  );
  static const BoundedDeletePolicy _skillDeletePolicy = BoundedDeletePolicy(
    maxEntries: _maxInstalledSkillScanEntries,
    maxDepth: _maxSkillScanDepth,
    totalTimeout: Duration(minutes: 1),
  );
  static final RegExp _windowsDrivePrefixPattern = RegExp(r'^[a-zA-Z]:');
  static final RegExp _titleSegmentSeparatorPattern = RegExp(r'[-_]+');
  static final RegExp _slugUnsafeCharsPattern = RegExp(r'[^a-z0-9]+');
  static final RegExp _slugEdgeHyphenPattern = RegExp(r'^-+|-+$');

  Future<Directory> ensureStorageDirectory(String storagePath) async {
    final directory = Directory(storagePath);
    return createDirectoryBounded(directory);
  }

  Future<List<LocalSkill>> loadInstalledSkills(String storagePath) async {
    final directory = await ensureStorageDirectory(storagePath);
    final skills = <LocalSkill>[];
    await _scanSkillManifests(
      directory,
      maxEntries: _maxInstalledSkillScanEntries,
      acceptManifest: (file) async {
        try {
          skills.add(await _parseSkill(file, storagePath));
          return true;
        } catch (error, stack) {
          silentLog('skills_repository', '解析已安装技能 ${file.path}', error, stack);
          return false;
        }
      },
    );

    skills.sort(
      (left, right) =>
          left.name.toLowerCase().compareTo(right.name.toLowerCase()),
    );
    return skills;
  }

  Future<LocalSkill> createSkillTemplate(String storagePath) async {
    final directory = await ensureStorageDirectory(storagePath);
    final targetDirectory = await _createUniqueSkillDirectory(directory);
    final skillSlug = OpenHandPaths.basename(targetDirectory.path);
    final skillName = _titleFromSlug(skillSlug);
    final manifestFile = File(p.join(targetDirectory.path, _manifestFileName));
    final templateContent = _buildTemplate(skillName);

    try {
      await writeFileAtomically(manifestFile, templateContent);
      await _writeOpenAiMetadata(
        targetDirectory.path,
        displayName: skillName,
        shortDescription: _defaultTemplateDescription,
        emojiIcon: _defaultTemplateIcon,
        defaultPrompt: _deriveDefaultPrompt(
          templateContent,
          fallback: _defaultTemplateDescription,
        ),
      );
      return await _parseSkill(manifestFile, storagePath);
    } catch (error, stack) {
      return _throwAfterFailedSkillDirectoryOperation(
        action: '创建技能模板',
        error: error,
        stack: stack,
        directory: targetDirectory,
        storageRootPath: storagePath,
      );
    }
  }

  Future<LocalSkill> createSkill(
    String storagePath, {
    required String name,
    String? emojiIcon,
    Uint8List? imageIconBytes,
    required String shortDescription,
    required String manifestContent,
  }) async {
    final input = _normalizeSkillInput(
      name: name,
      shortDescription: shortDescription,
      manifestContent: manifestContent,
      emojiIcon: emojiIcon,
      imageIconBytes: imageIconBytes,
    );
    final normalizedName = input.name;
    final normalizedShortDescription = input.description;
    final normalizedEmojiIcon = input.emojiIcon;
    final normalizedImageIconBytes = input.imageIconBytes;

    final directory = await ensureStorageDirectory(storagePath);
    final targetDirectory = await _createUniqueSkillDirectory(
      directory,
      preferredSlug: _slugify(normalizedName),
    );
    final manifestFile = File(p.join(targetDirectory.path, _manifestFileName));
    final defaultPrompt = _deriveDefaultPrompt(
      manifestContent,
      fallback: normalizedShortDescription,
    );

    try {
      await writeFileAtomically(
        manifestFile,
        _buildSkillDocument(
          skillName: normalizedName,
          emojiIcon: normalizedEmojiIcon,
          description: normalizedShortDescription,
          rawContent: manifestContent,
        ),
      );
      await _writeOpenAiMetadata(
        targetDirectory.path,
        displayName: normalizedName,
        shortDescription: normalizedShortDescription,
        emojiIcon: normalizedEmojiIcon,
        imageIconBytes: normalizedImageIconBytes,
        defaultPrompt: defaultPrompt,
      );
      return await _parseSkill(manifestFile, storagePath);
    } catch (error, stack) {
      return _throwAfterFailedSkillDirectoryOperation(
        action: '创建技能',
        error: error,
        stack: stack,
        directory: targetDirectory,
        storageRootPath: storagePath,
      );
    }
  }

  Future<LocalSkill> importSkillDirectory(
    String storagePath,
    String sourceDirectoryPath,
  ) async {
    final storageDirectory = await ensureStorageDirectory(storagePath);
    final sourceDirectory = Directory(sourceDirectoryPath);
    if (!await isDirectoryPath(sourceDirectory.path, followLinks: true)) {
      throw const FileSystemException('源技能目录不存在或不可访问。');
    }

    final sourceManifest = File(
      p.join(sourceDirectory.path, _manifestFileName),
    );
    if (!await regularFileExistsBounded(sourceManifest, followLinks: false)) {
      throw const FileSystemException('技能清单文件不存在。');
    }

    final normalizedStoragePath = p.normalize(storageDirectory.path);
    final normalizedSourcePath = p.normalize(sourceDirectory.path);
    final parsedSourceSkill = await _parseSkill(sourceManifest, storagePath);
    if (isPathWithinOrEqual(normalizedStoragePath, normalizedSourcePath)) {
      return parsedSourceSkill;
    }

    final targetDirectory = await _createUniqueSkillDirectory(
      storageDirectory,
      preferredSlug: _slugify(OpenHandPaths.basename(sourceDirectory.path)),
    );
    try {
      await copyDirectoryBounded(
        sourceDirectory,
        targetDirectory,
        policy: _directoryImportCopyPolicy,
        allowExistingEmptyTarget: true,
      );
      return await _parseSkill(
        File(p.join(targetDirectory.path, _manifestFileName)),
        storagePath,
      );
    } catch (error, stack) {
      return _throwAfterFailedSkillDirectoryOperation(
        action: '导入技能目录',
        error: error,
        stack: stack,
        directory: targetDirectory,
        storageRootPath: storagePath,
      );
    }
  }

  Future<LocalSkill> installSkillArchive(
    String storagePath, {
    required String preferredSlug,
    required Uint8List archiveBytes,
  }) async {
    if (archiveBytes.isEmpty) {
      throw const FileSystemException('技能归档为空。');
    }

    final storageDirectory = await ensureStorageDirectory(storagePath);
    final targetDirectory = await _createUniqueSkillDirectory(
      storageDirectory,
      preferredSlug: _slugify(preferredSlug),
    );

    try {
      final archive = BoundedZipArchive.decode(
        archiveBytes,
        maxEntries: _maxArchiveEntries,
        maxReadBytes: _maxExtractedArchiveBytes,
      );
      await _extractSkillArchive(archive, targetDirectory);
      final manifestFile = await _findFirstSkillManifest(targetDirectory);
      if (manifestFile == null) {
        throw const FileSystemException('技能归档中缺少 SKILL.md。');
      }
      return await _parseSkill(manifestFile, storagePath);
    } catch (error, stack) {
      return _throwAfterFailedSkillDirectoryOperation(
        action: '安装技能归档',
        error: error,
        stack: stack,
        directory: targetDirectory,
        storageRootPath: storagePath,
      );
    }
  }

  Future<String> readSkillManifest(LocalSkill skill) {
    return readBoundedFileString(
      File(skill.manifestPath),
      maxBytes: skillManifestMaxBytes,
    );
  }

  Future<LocalSkill> updateSkillManifest(
    LocalSkill skill,
    String storagePath,
    String content,
  ) async {
    if (nullIfBlank(content) == null) {
      throw const FileSystemException('技能清单为空。');
    }

    final manifestFile = File(skill.manifestPath);
    final normalizedContent = content.replaceAll('\r\n', '\n');
    final skillDirectoryPath = manifestFile.parent.path;
    final metadataPath = p.join(
      skillDirectoryPath,
      _openAiMetadataRelativePath,
    );
    final previousManifestContent = await readBoundedFileString(
      manifestFile,
      maxBytes: skillManifestMaxBytes,
    );
    final previousMetadataBytes = await _readOptionalFileBytes(metadataPath);

    try {
      await writeFileAtomically(manifestFile, normalizedContent);
      await _syncOpenAiMetadataWithManifest(
        skillDirectoryPath: skillDirectoryPath,
        content: normalizedContent,
        fallbackSkill: skill,
      );
      return await _parseSkill(manifestFile, storagePath);
    } catch (error, stack) {
      return _throwAfterFailedSkillUpdate(
        action: '更新技能清单',
        error: error,
        stack: stack,
        manifestFile: manifestFile,
        previousManifestContent: previousManifestContent,
        previousOptionalFiles: <String, Uint8List?>{
          metadataPath: previousMetadataBytes,
        },
        rootDirectoryPath: skillDirectoryPath,
      );
    }
  }

  Future<LocalSkill> updateSkill(
    LocalSkill skill,
    String storagePath, {
    required String name,
    String? emojiIcon,
    Uint8List? imageIconBytes,
    required String shortDescription,
    required String manifestContent,
    bool preserveExistingIcon = false,
  }) async {
    final input = _normalizeSkillInput(
      name: name,
      shortDescription: shortDescription,
      manifestContent: manifestContent,
      emojiIcon: emojiIcon,
      imageIconBytes: imageIconBytes,
      allowMissingIcon: preserveExistingIcon,
    );
    final normalizedName = input.name;
    final normalizedShortDescription = input.description;
    final normalizedEmojiIcon = input.emojiIcon;
    final normalizedImageIconBytes = input.imageIconBytes;

    final rebuiltContent = _buildSkillDocument(
      skillName: normalizedName,
      emojiIcon: normalizedEmojiIcon,
      description: normalizedShortDescription,
      rawContent: manifestContent,
    );
    final manifestFile = File(skill.manifestPath);
    final skillDirectoryPath = manifestFile.parent.path;
    final metadataPath = p.join(
      skillDirectoryPath,
      _openAiMetadataRelativePath,
    );
    final generatedEmojiIconPath = p.join(
      skillDirectoryPath,
      _openAiAssetsRelativePath,
      _generatedEmojiIconFileName,
    );
    final generatedImageIconPath = p.join(
      skillDirectoryPath,
      _openAiAssetsRelativePath,
      _generatedImageIconFileName,
    );
    final previousManifestContent = await readBoundedFileString(
      manifestFile,
      maxBytes: skillManifestMaxBytes,
    );
    final previousMetadataBytes = await _readOptionalFileBytes(metadataPath);
    final previousEmojiIconBytes = await _readOptionalFileBytes(
      generatedEmojiIconPath,
    );
    final previousImageIconBytes = await _readOptionalFileBytes(
      generatedImageIconPath,
    );

    try {
      await writeFileAtomically(manifestFile, rebuiltContent);
      if (preserveExistingIcon) {
        await _syncOpenAiMetadataWithManifest(
          skillDirectoryPath: skillDirectoryPath,
          content: rebuiltContent,
          fallbackSkill: skill,
        );
      } else {
        await _writeOpenAiMetadata(
          skillDirectoryPath,
          displayName: normalizedName,
          shortDescription: normalizedShortDescription,
          emojiIcon: normalizedEmojiIcon,
          imageIconBytes: normalizedImageIconBytes,
          defaultPrompt: _deriveDefaultPrompt(
            rebuiltContent,
            fallback: normalizedShortDescription,
          ),
        );
      }
      return await _parseSkill(manifestFile, storagePath);
    } catch (error, stack) {
      return _throwAfterFailedSkillUpdate(
        action: '更新技能',
        error: error,
        stack: stack,
        manifestFile: manifestFile,
        previousManifestContent: previousManifestContent,
        previousOptionalFiles: <String, Uint8List?>{
          metadataPath: previousMetadataBytes,
          generatedEmojiIconPath: previousEmojiIconBytes,
          generatedImageIconPath: previousImageIconBytes,
        },
        rootDirectoryPath: skillDirectoryPath,
      );
    }
  }

  Future<void> deleteSkill(LocalSkill skill, String storagePath) async {
    final directory = Directory(skill.directoryPath);
    if (!await isDirectoryPath(directory.path)) {
      throw const FileSystemException('技能目录不存在或不可访问。');
    }

    final normalizedDirectoryPath = p.normalize(directory.path);
    final normalizedStoragePath = p.normalize(storagePath);
    if (p.equals(normalizedDirectoryPath, normalizedStoragePath) ||
        !isPathWithinOrEqual(normalizedStoragePath, normalizedDirectoryPath)) {
      throw const FileSystemException('技能目录不在存储根目录内。');
    }

    await deletePathBounded(
      p.absolute(directory.path),
      policy: _skillDeletePolicy,
      allowMissing: false,
      allowedRoot: p.absolute(storagePath),
    );
  }

  Future<void> openDirectory(String path) async {
    final directory = Directory(path);
    return openDirectoryInFileManager(directory, createIfMissing: false);
  }

  Future<LocalSkill> _parseSkill(File manifestFile, String storagePath) async {
    final lines = (await readBoundedFileString(
      manifestFile,
      maxBytes: skillManifestMaxBytes,
    )).split('\n');
    final metadata = _extractFrontMatter(lines);
    final directoryPath = manifestFile.parent.path;
    final relativeDirectoryPath = p.relative(directoryPath, from: storagePath);
    final fallbackName = _titleFromSlug(OpenHandPaths.basename(directoryPath));
    final description = metadata['description'] ?? _extractDescription(lines);
    final openAiMetadata = await _loadOpenAiMetadata(directoryPath);
    final resolvedName = _sanitizeDisplayValue(metadata['name']);
    final resolvedDescription = _sanitizeDisplayValue(description);

    return LocalSkill(
      name: openAiMetadata?.displayName ?? resolvedName ?? fallbackName,
      description:
          openAiMetadata?.shortDescription ??
          resolvedDescription ??
          fallbackName,
      directoryPath: directoryPath,
      manifestPath: manifestFile.path,
      relativeDirectoryPath: relativeDirectoryPath,
      defaultPrompt: openAiMetadata?.defaultPrompt,
      emojiIcon: _sanitizeEmojiIcon(metadata['icon']),
      iconPath: openAiMetadata?.iconPath,
      iconKind: openAiMetadata?.iconKind,
    );
  }

  Map<String, String> _extractFrontMatter(List<String> lines) {
    if (lines.isEmpty || lines.first.trim() != '---') {
      return const <String, String>{};
    }

    final metadata = <String, String>{};
    for (var index = 1; index < lines.length; index++) {
      final line = lines[index].trim();
      if (line == '---') {
        break;
      }
      final separatorIndex = line.indexOf(':');
      if (separatorIndex <= 0) {
        continue;
      }
      final key = line.substring(0, separatorIndex).trim().toLowerCase();
      final value = _normalizeFrontMatterValue(
        line.substring(separatorIndex + 1),
      );
      if (value.isNotEmpty) {
        metadata[key] = value;
      }
    }
    return metadata;
  }

  String _extractDescription(List<String> lines) {
    var inFrontMatter = false;
    var frontMatterClosed = false;
    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line == '---' && !inFrontMatter && !frontMatterClosed) {
        inFrontMatter = true;
        continue;
      }
      if (line == '---' && inFrontMatter) {
        inFrontMatter = false;
        frontMatterClosed = true;
        continue;
      }
      if (inFrontMatter || line.isEmpty || line.startsWith('#')) {
        continue;
      }
      return line;
    }
    return '';
  }

  Future<_OpenAiSkillMetadata?> _loadOpenAiMetadata(
    String directoryPath,
  ) async {
    final document = await _readOpenAiMetadataDocument(directoryPath);
    if (document == null) {
      return null;
    }

    try {
      final icon = await _resolveOpenAiIcon(
        skillDirectoryPath: directoryPath,
        metadataDirectoryPath: p.join(directoryPath, 'agents'),
        rawPaths: <String?>[document.iconSmallPath, document.iconLargePath],
      );
      return _OpenAiSkillMetadata(
        displayName: document.displayName,
        shortDescription: document.shortDescription,
        defaultPrompt: document.defaultPrompt,
        iconPath: icon?.path,
        iconKind: icon?.kind,
      );
    } catch (error, stack) {
      silentLog('skills_repository', '加载 OpenAI 元数据', error, stack);
      return null;
    }
  }

  Future<_OpenAiMetadataDocument?> _readOpenAiMetadataDocument(
    String directoryPath,
  ) async {
    final metadataFile = File(
      p.join(directoryPath, _openAiMetadataRelativePath),
    );
    if (!await isRegularFilePath(metadataFile.path)) {
      return null;
    }

    try {
      final rawContent = await readBoundedFileString(
        metadataFile,
        maxBytes: _maxMetadataBytes,
      );
      final decoded = loadYaml(rawContent);
      if (decoded is! YamlMap) {
        return null;
      }
      final interface = decoded['interface'];
      if (interface is! YamlMap) {
        return null;
      }

      return _OpenAiMetadataDocument(
        displayName: _sanitizeDisplayValue(
          _readYamlString(interface['display_name']),
        ),
        shortDescription: _sanitizeDisplayValue(
          _readYamlString(interface['short_description']),
        ),
        defaultPrompt: _sanitizeDisplayValue(
          _readYamlString(interface['default_prompt']),
        ),
        iconSmallPath: _sanitizeDisplayValue(
          _readYamlString(interface['icon_small']),
        ),
        iconLargePath: _sanitizeDisplayValue(
          _readYamlString(interface['icon_large']),
        ),
      );
    } catch (error, stack) {
      silentLog('skills_repository', '读取 OpenAI 元数据文档', error, stack);
      return null;
    }
  }

  Future<_ResolvedSkillIcon?> _resolveOpenAiIcon({
    required String skillDirectoryPath,
    required String metadataDirectoryPath,
    required List<String?> rawPaths,
  }) async {
    for (final rawPath in rawPaths) {
      final resolvedIcon = await _resolveOpenAiIconCandidate(
        rawPath,
        skillDirectoryPath: skillDirectoryPath,
        metadataDirectoryPath: metadataDirectoryPath,
      );
      if (resolvedIcon != null) {
        return resolvedIcon;
      }
    }
    return null;
  }

  Future<_ResolvedSkillIcon?> _resolveOpenAiIconCandidate(
    String? rawPath, {
    required String skillDirectoryPath,
    required String metadataDirectoryPath,
  }) async {
    final sanitizedPath = _sanitizeDisplayValue(rawPath);
    if (sanitizedPath == null) {
      return null;
    }

    if (safeRelativePathError(sanitizedPath) != null) {
      return null;
    }
    final normalizedPath = p.normalize(sanitizedPath);

    final extension = p.extension(normalizedPath).toLowerCase();
    final iconKind = switch (extension) {
      '.svg' => LocalSkillIconKind.svg,
      '.png' ||
      '.jpg' ||
      '.jpeg' ||
      '.webp' ||
      '.gif' => LocalSkillIconKind.raster,
      _ => null,
    };
    if (iconKind == null) {
      return null;
    }

    final candidatePaths = <String>[
      p.normalize(p.join(metadataDirectoryPath, sanitizedPath)),
      p.normalize(p.join(skillDirectoryPath, sanitizedPath)),
    ];
    for (final candidatePath in candidatePaths) {
      if (!isPathWithinOrEqual(skillDirectoryPath, candidatePath) &&
          !isPathWithinOrEqual(metadataDirectoryPath, candidatePath)) {
        continue;
      }
      final iconFile = File(candidatePath);
      if (await isRegularFilePath(iconFile.path)) {
        return _ResolvedSkillIcon(path: candidatePath, kind: iconKind);
      }
    }
    return null;
  }

  String? _readYamlString(Object? value) {
    if (value is! String) {
      return null;
    }
    return value.trim();
  }

  String _normalizeFrontMatterValue(String value) {
    final trimmedValue = value.trim();
    if (trimmedValue.length < 2) {
      return trimmedValue;
    }
    final startsWithDoubleQuote = trimmedValue.startsWith('"');
    final endsWithDoubleQuote = trimmedValue.endsWith('"');
    final startsWithSingleQuote = trimmedValue.startsWith("'");
    final endsWithSingleQuote = trimmedValue.endsWith("'");
    if ((startsWithDoubleQuote && endsWithDoubleQuote) ||
        (startsWithSingleQuote && endsWithSingleQuote)) {
      return trimmedValue.substring(1, trimmedValue.length - 1).trim();
    }
    return trimmedValue;
  }

  /// 创建与更新共用的技能入参校验与规整。
  ///
  /// 任一必填项缺失即抛出，避免落盘半成品；[allowMissingIcon] 用于「沿用已有
  /// 图标」的更新路径，此时允许两个图标入参同时为空。
  ({
    String name,
    String description,
    String? emojiIcon,
    Uint8List? imageIconBytes,
  })
  _normalizeSkillInput({
    required String name,
    required String shortDescription,
    required String manifestContent,
    String? emojiIcon,
    Uint8List? imageIconBytes,
    bool allowMissingIcon = false,
  }) {
    final normalizedName = _sanitizeDisplayValue(name);
    if (normalizedName == null) {
      throw const FileSystemException('技能名称为空。');
    }
    final normalizedShortDescription = _sanitizeDisplayValue(shortDescription);
    if (normalizedShortDescription == null) {
      throw const FileSystemException('技能描述为空。');
    }
    if (nullIfBlank(manifestContent) == null) {
      throw const FileSystemException('技能清单为空。');
    }
    final normalizedEmojiIcon = _sanitizeEmojiIcon(emojiIcon);
    final normalizedImageIconBytes =
        imageIconBytes != null && imageIconBytes.isNotEmpty
        ? Uint8List.fromList(imageIconBytes)
        : null;
    if (!allowMissingIcon &&
        normalizedEmojiIcon == null &&
        normalizedImageIconBytes == null) {
      throw const FileSystemException('技能图标为空。');
    }
    return (
      name: normalizedName,
      description: normalizedShortDescription,
      emojiIcon: normalizedEmojiIcon,
      imageIconBytes: normalizedImageIconBytes,
    );
  }

  String? _sanitizeDisplayValue(String? value) {
    return nullIfBlank(value);
  }

  String? _sanitizeEmojiIcon(String? value) {
    final sanitizedValue = _sanitizeDisplayValue(value);
    if (sanitizedValue == null) {
      return null;
    }
    return sanitizedValue.characters.first;
  }

  String _buildSkillDocument({
    required String skillName,
    String? emojiIcon,
    required String description,
    required String rawContent,
  }) {
    final document = _extractManifestDocument(rawContent);
    final metadata = <String, String>{
      'name': skillName,
      'description': description,
    };
    if (emojiIcon != null) {
      metadata['icon'] = emojiIcon;
    }
    for (final entry in document.metadata.entries) {
      if (entry.key == 'name' ||
          entry.key == 'icon' ||
          entry.key == 'description') {
        continue;
      }
      metadata[entry.key] = entry.value;
    }

    final buffer = StringBuffer();
    buffer.writeln('---');
    for (final entry in metadata.entries) {
      buffer.writeln('${entry.key}: "${_escapeQuotedYamlValue(entry.value)}"');
    }
    buffer.writeln('---');
    buffer.writeln();
    buffer.write(document.body.trim());
    if (!document.body.trim().endsWith('\n')) {
      buffer.writeln();
    }
    return buffer.toString();
  }

  Future<void> _writeOpenAiMetadata(
    String skillDirectoryPath, {
    required String displayName,
    required String shortDescription,
    String? emojiIcon,
    Uint8List? imageIconBytes,
    required String defaultPrompt,
  }) async {
    final metadataFile = File(
      p.join(skillDirectoryPath, _openAiMetadataRelativePath),
    );

    final generatedEmojiIconPath = p.join(
      skillDirectoryPath,
      _openAiAssetsRelativePath,
      _generatedEmojiIconFileName,
    );
    final generatedImageIconPath = p.join(
      skillDirectoryPath,
      _openAiAssetsRelativePath,
      _generatedImageIconFileName,
    );
    String? iconRelativePath;
    if (imageIconBytes != null && imageIconBytes.isNotEmpty) {
      await _deleteOptionalFileIfExists(generatedEmojiIconPath);
      final iconFile = File(generatedImageIconPath);
      await writeBytesFileAtomically(iconFile, imageIconBytes);
      iconRelativePath = './assets/$_generatedImageIconFileName';
    } else {
      await _deleteOptionalFileIfExists(generatedImageIconPath);
      final normalizedEmojiIcon = _sanitizeEmojiIcon(emojiIcon);
      if (normalizedEmojiIcon != null) {
        final iconFile = File(generatedEmojiIconPath);
        await writeFileAtomically(
          iconFile,
          _buildEmojiIconSvg(normalizedEmojiIcon),
        );
        iconRelativePath = './assets/$_generatedEmojiIconFileName';
      }
    }

    await writeFileAtomically(
      metadataFile,
      _buildOpenAiMetadataDocument(
        displayName: displayName,
        shortDescription: shortDescription,
        iconSmallRelativePath: iconRelativePath,
        iconLargeRelativePath: iconRelativePath,
        defaultPrompt: defaultPrompt,
      ),
    );
  }

  Future<void> _syncOpenAiMetadataWithManifest({
    required String skillDirectoryPath,
    required String content,
    required LocalSkill fallbackSkill,
  }) async {
    final existingMetadata = await _readOpenAiMetadataDocument(
      skillDirectoryPath,
    );
    if (existingMetadata == null) {
      return;
    }

    final normalizedContent = content.replaceAll('\r\n', '\n');
    final lines = normalizedContent.split('\n');
    final metadata = _extractFrontMatter(lines);
    final resolvedName =
        _sanitizeDisplayValue(metadata['name']) ??
        existingMetadata.displayName ??
        fallbackSkill.name;
    final resolvedDescription =
        _sanitizeDisplayValue(
          metadata['description'] ?? _extractDescription(lines),
        ) ??
        existingMetadata.shortDescription ??
        fallbackSkill.description;
    final defaultPrompt = _deriveDefaultPrompt(
      normalizedContent,
      fallback: existingMetadata.defaultPrompt ?? resolvedDescription,
    );
    final metadataFile = File(
      p.join(skillDirectoryPath, _openAiMetadataRelativePath),
    );

    await writeFileAtomically(
      metadataFile,
      _buildOpenAiMetadataDocument(
        displayName: resolvedName,
        shortDescription: resolvedDescription,
        iconSmallRelativePath: existingMetadata.iconSmallPath,
        iconLargeRelativePath: existingMetadata.iconLargePath,
        defaultPrompt: defaultPrompt,
      ),
    );
  }

  String _buildOpenAiMetadataDocument({
    required String displayName,
    required String shortDescription,
    String? iconSmallRelativePath,
    String? iconLargeRelativePath,
    required String defaultPrompt,
  }) {
    final resolvedIconSmallPath =
        iconSmallRelativePath ?? iconLargeRelativePath;
    final resolvedIconLargePath =
        iconLargeRelativePath ?? iconSmallRelativePath;
    final buffer = StringBuffer()..writeln('interface:');
    buffer.writeln('  display_name: "${_escapeQuotedYamlValue(displayName)}"');
    buffer.writeln(
      '  short_description: "${_escapeQuotedYamlValue(shortDescription)}"',
    );
    if (resolvedIconSmallPath != null) {
      buffer.writeln(
        '  icon_small: "${_escapeQuotedYamlValue(resolvedIconSmallPath)}"',
      );
    }
    if (resolvedIconLargePath != null) {
      buffer.writeln(
        '  icon_large: "${_escapeQuotedYamlValue(resolvedIconLargePath)}"',
      );
    }
    buffer.writeln(
      '  default_prompt: "${_escapeQuotedYamlValue(defaultPrompt)}"',
    );
    return buffer.toString();
  }

  String _deriveDefaultPrompt(String rawContent, {required String fallback}) {
    final body = _extractManifestDocument(rawContent).body;
    for (final rawLine in body.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) {
        continue;
      }
      return line.replaceAll(kInlineWhitespacePattern, ' ');
    }
    return fallback;
  }

  String _buildEmojiIconSvg(String emoji) {
    final escapedEmoji = escapeXmlAttribute(emoji);
    return '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128">
  <rect width="128" height="128" rx="32" fill="#B7C957"/>
  <text x="64" y="80" text-anchor="middle" font-size="68">$escapedEmoji</text>
</svg>
''';
  }

  _SkillManifestDocument _extractManifestDocument(String content) {
    final normalizedContent = content.replaceAll('\r\n', '\n');
    final lines = normalizedContent.split('\n');
    final metadata = _extractFrontMatter(lines);
    if (lines.isEmpty || lines.first.trim() != '---') {
      return _SkillManifestDocument(
        metadata: metadata,
        body: normalizedContent.trim(),
      );
    }

    for (var index = 1; index < lines.length; index++) {
      if (lines[index].trim() != '---') {
        continue;
      }
      final body = lines.sublist(index + 1).join('\n').trim();
      return _SkillManifestDocument(metadata: metadata, body: body);
    }
    return _SkillManifestDocument(
      metadata: metadata,
      body: normalizedContent.trim(),
    );
  }

  String _escapeQuotedYamlValue(String value) {
    return value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
  }

  Future<Directory> _createUniqueSkillDirectory(
    Directory rootDirectory, {
    String? preferredSlug,
  }) async {
    final baseSlug = nullIfBlank(preferredSlug) ?? _defaultSkillSlug;
    for (var index = 1; index < 1000; index++) {
      final suffix = index == 1 ? '' : '-$index';
      final directory = Directory(
        p.join(rootDirectory.path, '$baseSlug$suffix'),
      );
      if (await probeFileSystemEntityType(directory.path) ==
          FileSystemEntityType.notFound) {
        await createDirectoryBounded(directory, timeout: _skillScanIdleTimeout);
        return directory;
      }
    }
    throw const FileSystemException('无法分配新的技能目录。');
  }

  Future<void> _extractSkillArchive(
    BoundedZipArchive archive,
    Directory targetDirectory,
  ) async {
    if (archive.files.length > _maxArchiveEntries) {
      throw const FileSystemException('技能归档条目过多。');
    }

    final entries = <_ArchiveEntryPlan>[];
    var extractedBytes = 0;
    for (final file in archive.files) {
      final pathParts = _sanitizeArchiveEntryPath(file.name);
      if (pathParts.isEmpty || _shouldSkipArchiveEntry(pathParts)) {
        continue;
      }
      if (file.isFile) {
        extractedBytes += file.size;
        if (extractedBytes > _maxExtractedArchiveBytes) {
          throw const FileSystemException('技能归档解压后过大。');
        }
      }
      entries.add(_ArchiveEntryPlan(file: file, pathParts: pathParts));
    }

    if (entries.isEmpty) {
      throw const FileSystemException('技能归档中没有文件。');
    }

    final commonRoot = _singleArchiveRootDirectory(entries);
    final extractionEntries = <_ArchiveEntryPlan>[];
    final occupiedPaths = <String>{};
    final filePaths = <String>{};
    final requiredDirectoryPaths = <String>{};
    final caseInsensitivePaths = Platform.isMacOS || Platform.isWindows;
    for (final entry in entries) {
      final relativeParts = commonRoot == null
          ? entry.pathParts
          : entry.pathParts.skip(1).toList(growable: false);
      if (relativeParts.isEmpty) {
        continue;
      }
      if (relativeParts.length > _maxSkillScanDepth) {
        throw const FileSystemException('技能归档路径层级过深。');
      }

      final relativePath = p.posix.joinAll(relativeParts);
      if (relativePath.length > _maxArchivePathCharacters) {
        throw const FileSystemException('技能归档路径过长。');
      }
      final pathKey = caseInsensitivePaths
          ? relativePath.toLowerCase()
          : relativePath;
      if (!occupiedPaths.add(pathKey)) {
        throw const FileSystemException('技能归档包含重复路径。');
      }

      var ancestorPath = '';
      for (var index = 0; index < relativeParts.length - 1; index++) {
        ancestorPath = ancestorPath.isEmpty
            ? relativeParts[index]
            : '$ancestorPath/${relativeParts[index]}';
        final ancestorKey = caseInsensitivePaths
            ? ancestorPath.toLowerCase()
            : ancestorPath;
        if (filePaths.contains(ancestorKey)) {
          throw const FileSystemException('技能归档包含文件与目录路径冲突。');
        }
        requiredDirectoryPaths.add(ancestorKey);
      }
      if (entry.file.isFile) {
        if (requiredDirectoryPaths.contains(pathKey)) {
          throw const FileSystemException('技能归档包含文件与目录路径冲突。');
        }
        filePaths.add(pathKey);
      } else {
        requiredDirectoryPaths.add(pathKey);
      }
      extractionEntries.add(
        _ArchiveEntryPlan(file: entry.file, pathParts: relativeParts),
      );
    }

    for (final entry in extractionEntries) {
      final destinationPath = p.normalize(
        p.joinAll(<String>[targetDirectory.path, ...entry.pathParts]),
      );
      if (!isPathWithinOrEqual(targetDirectory.path, destinationPath)) {
        throw const FileSystemException('技能归档路径不安全。');
      }

      if (entry.file.isDirectory) {
        await createDirectoryBounded(
          Directory(destinationPath),
          timeout: _skillScanIdleTimeout,
        );
        continue;
      }

      final content = entry.file.readBytes(maxBytes: _maxExtractedArchiveBytes);
      final outputFile = File(destinationPath);
      await writeBytesFileAtomically(outputFile, content);
    }
  }

  List<String> _sanitizeArchiveEntryPath(String rawPath) {
    if (rawPath.length > _maxArchivePathCharacters) {
      throw const FileSystemException('技能归档路径过长。');
    }
    if (rawPath.contains('\u0000')) {
      throw const FileSystemException('技能归档路径不安全。');
    }
    final normalizedPath = p.posix.normalize(rawPath.replaceAll(r'\', '/'));
    if (normalizedPath == '.' || nullIfBlank(normalizedPath) == null) {
      return const <String>[];
    }
    if (p.posix.isAbsolute(normalizedPath) ||
        normalizedPath.startsWith('../') ||
        normalizedPath == '..' ||
        _windowsDrivePrefixPattern.hasMatch(normalizedPath)) {
      throw const FileSystemException('技能归档路径不安全。');
    }

    final parts = p.posix
        .split(normalizedPath)
        .where((part) => part.isNotEmpty && part != '.')
        .toList(growable: false);
    if (parts.any((part) => part == '..' || !isPortableFileNamePart(part))) {
      throw const FileSystemException('技能归档路径不安全。');
    }
    return parts;
  }

  bool _shouldSkipArchiveEntry(List<String> pathParts) {
    if (pathParts.isEmpty) {
      return true;
    }
    final firstPart = pathParts.first;
    final lastPart = pathParts.last;
    return firstPart == '__MACOSX' || lastPart == '.DS_Store';
  }

  String? _singleArchiveRootDirectory(List<_ArchiveEntryPlan> entries) {
    String? root;
    for (final entry in entries) {
      if (entry.pathParts.isEmpty) {
        continue;
      }
      root ??= entry.pathParts.first;
      if (entry.pathParts.first != root) {
        return null;
      }
      if (entry.file.isFile && entry.pathParts.length == 1) {
        return null;
      }
    }
    return root;
  }

  Future<File?> _findFirstSkillManifest(Directory directory) async {
    final manifests = await _scanSkillManifests(
      directory,
      maxEntries: _maxArchiveEntries,
    );
    return manifests.isEmpty ? null : manifests.first;
  }

  Future<List<File>> _scanSkillManifests(
    Directory root, {
    required int maxEntries,
    Future<bool> Function(File manifest)? acceptManifest,
  }) async {
    final pending = Queue<({Directory directory, int depth})>()
      ..add((directory: root, depth: 0));
    final manifests = <File>[];
    final stopwatch = Stopwatch()..start();
    var visitedEntries = 0;

    void checkTotalTimeout() {
      if (stopwatch.elapsed >= _skillScanTotalTimeout) {
        throw TimeoutException('技能目录扫描超过总时限。', _skillScanTotalTimeout);
      }
    }

    try {
      while (pending.isNotEmpty) {
        checkTotalTimeout();
        final node = pending.removeFirst();
        final childDirectories = <Directory>[];
        File? manifest;
        await for (final entity
            in node.directory
                .list(followLinks: false)
                .timeout(_skillScanIdleTimeout)) {
          checkTotalTimeout();
          visitedEntries += 1;
          if (visitedEntries > maxEntries) {
            throw FileSystemException(
              '技能目录超过 $maxEntries 个条目的扫描上限。',
              root.path,
            );
          }
          if (entity is File && p.basename(entity.path) == _manifestFileName) {
            manifest = entity;
          } else if (entity is Directory) {
            childDirectories.add(entity);
          }
        }
        if (manifest != null) {
          final accepted =
              acceptManifest == null || await acceptManifest(manifest);
          checkTotalTimeout();
          if (accepted) {
            manifests.add(manifest);
            continue;
          }
        }
        if (childDirectories.isNotEmpty && node.depth >= _maxSkillScanDepth) {
          throw FileSystemException(
            '技能目录超过 $_maxSkillScanDepth 层深度上限。',
            node.directory.path,
          );
        }
        childDirectories.sort(
          (left, right) =>
              p.normalize(left.path).compareTo(p.normalize(right.path)),
        );
        for (final child in childDirectories) {
          pending.add((directory: child, depth: node.depth + 1));
        }
      }
      return manifests;
    } finally {
      stopwatch.stop();
    }
  }

  Future<void> _deleteDirectoryIfExists(
    Directory directory, {
    required String storageRootPath,
  }) {
    return deletePathBounded(
      p.absolute(directory.path),
      policy: _skillDeletePolicy,
      allowedRoot: p.absolute(storageRootPath),
    );
  }

  Future<void> _deleteOptionalFileIfExists(String filePath) async {
    await deleteFileAtomically(File(filePath));
  }

  Future<Uint8List?> _readOptionalFileBytes(String filePath) async {
    final file = File(filePath);
    if (!await regularFileExistsBounded(file, followLinks: false)) {
      return null;
    }
    return readBoundedFileBytes(
      file,
      maxBytes: _maxOptionalAssetBytes,
      idleTimeout: defaultBoundedFileReadIdleTimeout,
      totalTimeout: defaultBoundedFileReadTotalTimeout,
    );
  }

  Future<void> _restoreOptionalFile(
    String filePath,
    Uint8List? bytes, {
    required String rootDirectoryPath,
  }) async {
    final file = File(filePath);
    if (bytes == null) {
      await deleteFileAtomically(file);
      await deleteEmptyAncestorDirectories(
        start: file.parent,
        stopAt: Directory(rootDirectoryPath),
      );
      return;
    }

    await writeBytesFileAtomically(file, bytes);
  }

  Future<Never> _throwAfterFailedSkillDirectoryOperation({
    required String action,
    required Object error,
    required StackTrace stack,
    required Directory directory,
    required String storageRootPath,
  }) async {
    silentLog('skills_repository', action, error, stack);
    try {
      await _deleteDirectoryIfExists(
        directory,
        storageRootPath: storageRootPath,
      );
    } catch (cleanupError, cleanupStack) {
      silentLog(
        'skills_repository',
        '$action失败后清理目录',
        cleanupError,
        cleanupStack,
      );
    }
    Error.throwWithStackTrace(error, stack);
  }

  Future<Never> _throwAfterFailedSkillUpdate({
    required String action,
    required Object error,
    required StackTrace stack,
    required File manifestFile,
    required String previousManifestContent,
    required Map<String, Uint8List?> previousOptionalFiles,
    required String rootDirectoryPath,
  }) async {
    silentLog('skills_repository', action, error, stack);
    try {
      await writeFileAtomically(manifestFile, previousManifestContent);
    } catch (rollbackError, rollbackStack) {
      silentLog(
        'skills_repository',
        '$action失败后恢复技能清单',
        rollbackError,
        rollbackStack,
      );
    }
    for (final entry in previousOptionalFiles.entries) {
      try {
        await _restoreOptionalFile(
          entry.key,
          entry.value,
          rootDirectoryPath: rootDirectoryPath,
        );
      } catch (rollbackError, rollbackStack) {
        silentLog(
          'skills_repository',
          '$action失败后恢复关联文件',
          rollbackError,
          rollbackStack,
        );
      }
    }
    Error.throwWithStackTrace(error, stack);
  }

  String _titleFromSlug(String slug) {
    final words = slug
        .split(_titleSegmentSeparatorPattern)
        .where((segment) => segment.isNotEmpty)
        .map((segment) => '${segment[0].toUpperCase()}${segment.substring(1)}');
    return words.isEmpty ? 'New Skill' : words.join(' ');
  }

  String _slugify(String rawValue) {
    final normalized = rawValue
        .trim()
        .toLowerCase()
        .replaceAll(_slugUnsafeCharsPattern, '-')
        .replaceAll(_slugEdgeHyphenPattern, '');
    return normalized.isEmpty ? _defaultSkillSlug : normalized;
  }

  String _buildTemplate(String skillName) {
    return '''
---
name: $skillName
description: Describe what this skill does.
---

# $skillName

## Purpose

Explain the goal of this skill.

## Workflow

1. Describe the first step.
2. Describe the second step.

## Notes

Add any implementation details or constraints here.
''';
  }
}

class _OpenAiSkillMetadata {
  const _OpenAiSkillMetadata({
    this.displayName,
    this.shortDescription,
    this.defaultPrompt,
    this.iconPath,
    this.iconKind,
  });

  final String? displayName;
  final String? shortDescription;
  final String? defaultPrompt;
  final String? iconPath;
  final LocalSkillIconKind? iconKind;
}

class _OpenAiMetadataDocument {
  const _OpenAiMetadataDocument({
    this.displayName,
    this.shortDescription,
    this.defaultPrompt,
    this.iconSmallPath,
    this.iconLargePath,
  });

  final String? displayName;
  final String? shortDescription;
  final String? defaultPrompt;
  final String? iconSmallPath;
  final String? iconLargePath;
}

class _ResolvedSkillIcon {
  const _ResolvedSkillIcon({required this.path, required this.kind});

  final String path;
  final LocalSkillIconKind kind;
}

class _SkillManifestDocument {
  const _SkillManifestDocument({required this.metadata, required this.body});

  final Map<String, String> metadata;
  final String body;
}

class _ArchiveEntryPlan {
  const _ArchiveEntryPlan({required this.file, required this.pathParts});

  final BoundedZipEntry file;
  final List<String> pathParts;
}

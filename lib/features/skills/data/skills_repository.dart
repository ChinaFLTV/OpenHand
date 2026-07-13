import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:characters/characters.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../../../app/support/openhand_paths.dart';
import '../../../app/support/silent_log.dart';
import '../../../shared/db/atomic_file_operations.dart';
import '../../../shared/util/bounded_file_io.dart';
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
  static const int _maxExtractedArchiveBytes = 160 * 1024 * 1024;
  static const int _maxInstalledSkillScanEntries = 20000;
  static const int _maxSkillScanDepth = 32;
  static const Duration _skillScanIdleTimeout = Duration(seconds: 3);
  static const Duration _skillScanTotalTimeout = Duration(seconds: 20);
  static const int _maxManifestBytes = 2 * kBytesPerMiB;
  static const int _maxMetadataBytes = 512 * kBytesPerKiB;
  static const int _maxOptionalAssetBytes = 32 * kBytesPerMiB;
  static final RegExp _whitespacePattern = RegExp(r'\s+');
  static final RegExp _windowsDrivePrefixPattern = RegExp(r'^[a-zA-Z]:');
  static final RegExp _titleSegmentSeparatorPattern = RegExp(r'[-_]+');
  static final RegExp _slugUnsafeCharsPattern = RegExp(r'[^a-z0-9]+');
  static final RegExp _slugEdgeHyphenPattern = RegExp(r'^-+|-+$');

  Future<Directory> ensureStorageDirectory(String storagePath) async {
    final directory = Directory(storagePath);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
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
          silentLog(
            'skills_repository',
            'parse installed skill ${file.path}',
            error,
            stack,
          );
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
      return _parseSkill(manifestFile, storagePath);
    } catch (error, stack) {
      silentLog('skills_repository', 'create skill template', error, stack);
      await _deleteDirectoryIfExists(targetDirectory);
      rethrow;
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
    final normalizedName = _sanitizeDisplayValue(name);
    if (normalizedName == null) {
      throw const FileSystemException('Skill name is empty.');
    }
    final normalizedShortDescription = _sanitizeDisplayValue(shortDescription);
    if (normalizedShortDescription == null) {
      throw const FileSystemException('Skill description is empty.');
    }
    if (nullIfBlank(manifestContent) == null) {
      throw const FileSystemException('Skill manifest is empty.');
    }

    final directory = await ensureStorageDirectory(storagePath);
    final targetDirectory = await _createUniqueSkillDirectory(
      directory,
      preferredSlug: _slugify(normalizedName),
    );
    final manifestFile = File(p.join(targetDirectory.path, _manifestFileName));
    final normalizedEmojiIcon = _sanitizeEmojiIcon(emojiIcon);
    final normalizedImageIconBytes =
        imageIconBytes != null && imageIconBytes.isNotEmpty
        ? Uint8List.fromList(imageIconBytes)
        : null;
    if (normalizedEmojiIcon == null && normalizedImageIconBytes == null) {
      throw const FileSystemException('Skill icon is empty.');
    }
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
      return _parseSkill(manifestFile, storagePath);
    } catch (error, stack) {
      silentLog('skills_repository', 'create skill', error, stack);
      await _deleteDirectoryIfExists(targetDirectory);
      rethrow;
    }
  }

  Future<LocalSkill> importSkillDirectory(
    String storagePath,
    String sourceDirectoryPath,
  ) async {
    final storageDirectory = await ensureStorageDirectory(storagePath);
    final sourceDirectory = Directory(sourceDirectoryPath);
    if (!await sourceDirectory.exists()) {
      throw const FileSystemException('Source directory does not exist.');
    }

    final sourceManifest = File(
      p.join(sourceDirectory.path, _manifestFileName),
    );
    if (!await sourceManifest.exists()) {
      throw const FileSystemException('Skill manifest does not exist.');
    }

    final normalizedStoragePath = p.normalize(storageDirectory.path);
    final normalizedSourcePath = p.normalize(sourceDirectory.path);
    final relativeSourcePath = p.relative(
      normalizedSourcePath,
      from: normalizedStoragePath,
    );
    final parsedSourceSkill = await _parseSkill(sourceManifest, storagePath);
    if (relativeSourcePath == '.' || !relativeSourcePath.startsWith('..')) {
      return parsedSourceSkill;
    }

    final targetDirectory = await _createUniqueSkillDirectory(
      storageDirectory,
      preferredSlug: _slugify(OpenHandPaths.basename(sourceDirectory.path)),
    );
    try {
      await _copyDirectory(sourceDirectory, targetDirectory);
      return _parseSkill(
        File(p.join(targetDirectory.path, _manifestFileName)),
        storagePath,
      );
    } catch (error, stack) {
      silentLog('skills_repository', 'import skill directory', error, stack);
      await _deleteDirectoryIfExists(targetDirectory);
      rethrow;
    }
  }

  Future<LocalSkill> installSkillArchive(
    String storagePath, {
    required String preferredSlug,
    required Uint8List archiveBytes,
  }) async {
    if (archiveBytes.isEmpty) {
      throw const FileSystemException('Skill archive is empty.');
    }

    final storageDirectory = await ensureStorageDirectory(storagePath);
    final targetDirectory = await _createUniqueSkillDirectory(
      storageDirectory,
      preferredSlug: _slugify(preferredSlug),
    );

    try {
      final archive = ZipDecoder().decodeBytes(archiveBytes, verify: true);
      await _extractSkillArchive(archive, targetDirectory);
      final manifestFile = await _findFirstSkillManifest(targetDirectory);
      if (manifestFile == null) {
        throw const FileSystemException('Skill archive has no SKILL.md.');
      }
      return _parseSkill(manifestFile, storagePath);
    } catch (error, stack) {
      silentLog('skills_repository', 'install skill archive', error, stack);
      await _deleteDirectoryIfExists(targetDirectory);
      rethrow;
    }
  }

  Future<String> readSkillManifest(LocalSkill skill) {
    return readBoundedFileString(
      File(skill.manifestPath),
      maxBytes: _maxManifestBytes,
    );
  }

  Future<LocalSkill> updateSkillManifest(
    LocalSkill skill,
    String storagePath,
    String content,
  ) async {
    if (nullIfBlank(content) == null) {
      throw const FileSystemException('Skill manifest is empty.');
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
      maxBytes: _maxManifestBytes,
    );
    final previousMetadataBytes = await _readOptionalFileBytes(metadataPath);

    try {
      await writeFileAtomically(manifestFile, normalizedContent);
      await _syncOpenAiMetadataWithManifest(
        skillDirectoryPath: skillDirectoryPath,
        content: normalizedContent,
        fallbackSkill: skill,
      );
      return _parseSkill(manifestFile, storagePath);
    } catch (error, stack) {
      silentLog('skills_repository', 'update skill manifest', error, stack);
      await writeFileAtomically(manifestFile, previousManifestContent);
      await _restoreOptionalFile(
        metadataPath,
        previousMetadataBytes,
        rootDirectoryPath: skillDirectoryPath,
      );
      rethrow;
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
    final normalizedName = _sanitizeDisplayValue(name);
    if (normalizedName == null) {
      throw const FileSystemException('Skill name is empty.');
    }
    final normalizedShortDescription = _sanitizeDisplayValue(shortDescription);
    if (normalizedShortDescription == null) {
      throw const FileSystemException('Skill description is empty.');
    }
    if (nullIfBlank(manifestContent) == null) {
      throw const FileSystemException('Skill manifest is empty.');
    }

    final normalizedEmojiIcon = _sanitizeEmojiIcon(emojiIcon);
    final normalizedImageIconBytes =
        imageIconBytes != null && imageIconBytes.isNotEmpty
        ? Uint8List.fromList(imageIconBytes)
        : null;
    if (!preserveExistingIcon &&
        normalizedEmojiIcon == null &&
        normalizedImageIconBytes == null) {
      throw const FileSystemException('Skill icon is empty.');
    }

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
      maxBytes: _maxManifestBytes,
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
      return _parseSkill(manifestFile, storagePath);
    } catch (error, stack) {
      silentLog('skills_repository', 'update skill', error, stack);
      await writeFileAtomically(manifestFile, previousManifestContent);
      await _restoreOptionalFile(
        metadataPath,
        previousMetadataBytes,
        rootDirectoryPath: skillDirectoryPath,
      );
      await _restoreOptionalFile(
        generatedEmojiIconPath,
        previousEmojiIconBytes,
        rootDirectoryPath: skillDirectoryPath,
      );
      await _restoreOptionalFile(
        generatedImageIconPath,
        previousImageIconBytes,
        rootDirectoryPath: skillDirectoryPath,
      );
      rethrow;
    }
  }

  Future<void> deleteSkill(LocalSkill skill, String storagePath) async {
    final directory = Directory(skill.directoryPath);
    if (!await directory.exists()) {
      throw const FileSystemException('Skill directory does not exist.');
    }

    final relativeDirectoryPath = p.relative(
      p.normalize(directory.path),
      from: p.normalize(storagePath),
    );
    final isOutsideStorageRoot =
        relativeDirectoryPath == '.' || relativeDirectoryPath.startsWith('..');
    if (isOutsideStorageRoot) {
      throw const FileSystemException(
        'Skill directory is outside the storage root.',
      );
    }

    await directory.delete(recursive: true);
  }

  Future<void> openDirectory(String path) async {
    final directory = Directory(path);
    if (!await directory.exists()) {
      throw const FileSystemException('Directory does not exist.');
    }
    return openDirectoryInFileManager(directory);
  }

  Future<LocalSkill> _parseSkill(File manifestFile, String storagePath) async {
    final lines = (await readBoundedFileString(
      manifestFile,
      maxBytes: _maxManifestBytes,
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
      silentLog('skills_repository', 'load openai metadata', error, stack);
      return null;
    }
  }

  Future<_OpenAiMetadataDocument?> _readOpenAiMetadataDocument(
    String directoryPath,
  ) async {
    final metadataFile = File(
      p.join(directoryPath, _openAiMetadataRelativePath),
    );
    if (!await metadataFile.exists()) {
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
      silentLog(
        'skills_repository',
        'read openai metadata document',
        error,
        stack,
      );
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

    // Reject absolute paths to prevent path traversal attacks.
    if (p.isAbsolute(sanitizedPath)) {
      return null;
    }

    final normalizedPath = p.normalize(sanitizedPath);

    // Reject paths containing parent directory references.
    if (normalizedPath.contains('..')) {
      return null;
    }

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
      if (await iconFile.exists()) {
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
    if (!await metadataFile.parent.exists()) {
      await metadataFile.parent.create(recursive: true);
    }

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
      final assetsDirectory = Directory(
        p.join(skillDirectoryPath, _openAiAssetsRelativePath),
      );
      if (!await assetsDirectory.exists()) {
        await assetsDirectory.create(recursive: true);
      }
      final iconFile = File(generatedImageIconPath);
      await iconFile.writeAsBytes(imageIconBytes, flush: true);
      iconRelativePath = './assets/$_generatedImageIconFileName';
    } else {
      await _deleteOptionalFileIfExists(generatedImageIconPath);
      final normalizedEmojiIcon = _sanitizeEmojiIcon(emojiIcon);
      if (normalizedEmojiIcon != null) {
        final assetsDirectory = Directory(
          p.join(skillDirectoryPath, _openAiAssetsRelativePath),
        );
        if (!await assetsDirectory.exists()) {
          await assetsDirectory.create(recursive: true);
        }
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
      return line.replaceAll(_whitespacePattern, ' ');
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
      if (!await directory.exists()) {
        await directory.create(recursive: true);
        return directory;
      }
    }
    throw const FileSystemException(
      'Unable to allocate a new skill directory.',
    );
  }

  Future<void> _copyDirectory(Directory source, Directory target) async {
    await for (final entity in source.list(followLinks: false)) {
      final targetPath = p.join(
        target.path,
        OpenHandPaths.basename(entity.path),
      );
      if (entity is Directory) {
        final childDirectory = Directory(targetPath);
        await childDirectory.create(recursive: true);
        await _copyDirectory(entity, childDirectory);
        continue;
      }
      if (entity is File) {
        await entity.copy(targetPath);
      }
    }
  }

  Future<void> _extractSkillArchive(
    Archive archive,
    Directory targetDirectory,
  ) async {
    if (archive.files.length > _maxArchiveEntries) {
      throw const FileSystemException('Skill archive has too many entries.');
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
          throw const FileSystemException('Skill archive is too large.');
        }
      }
      entries.add(_ArchiveEntryPlan(file: file, pathParts: pathParts));
    }

    if (entries.isEmpty) {
      throw const FileSystemException('Skill archive has no files.');
    }

    final commonRoot = _singleArchiveRootDirectory(entries);
    for (final entry in entries) {
      final relativeParts = commonRoot == null
          ? entry.pathParts
          : entry.pathParts.skip(1).toList(growable: false);
      if (relativeParts.isEmpty) {
        continue;
      }

      final destinationPath = p.normalize(
        p.joinAll(<String>[targetDirectory.path, ...relativeParts]),
      );
      if (!isPathWithinOrEqual(targetDirectory.path, destinationPath)) {
        throw const FileSystemException('Skill archive path is unsafe.');
      }

      if (entry.file.isDirectory) {
        await Directory(destinationPath).create(recursive: true);
        continue;
      }

      final content = entry.file.readBytes();
      if (content == null) {
        throw const FileSystemException('Unable to read archive entry.');
      }
      final outputFile = File(destinationPath);
      if (!await outputFile.parent.exists()) {
        await outputFile.parent.create(recursive: true);
      }
      await outputFile.writeAsBytes(content, flush: true);
    }
  }

  List<String> _sanitizeArchiveEntryPath(String rawPath) {
    if (rawPath.contains('\u0000')) {
      throw const FileSystemException('Skill archive path is unsafe.');
    }
    final normalizedPath = p.posix.normalize(rawPath.replaceAll(r'\', '/'));
    if (normalizedPath == '.' || nullIfBlank(normalizedPath) == null) {
      return const <String>[];
    }
    if (p.posix.isAbsolute(normalizedPath) ||
        normalizedPath.startsWith('../') ||
        normalizedPath == '..' ||
        _windowsDrivePrefixPattern.hasMatch(normalizedPath)) {
      throw const FileSystemException('Skill archive path is unsafe.');
    }

    final parts = p.posix
        .split(normalizedPath)
        .where((part) => part.isNotEmpty && part != '.')
        .toList(growable: false);
    if (parts.any((part) => part == '..')) {
      throw const FileSystemException('Skill archive path is unsafe.');
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
        throw TimeoutException(
          'Skill directory scan exceeded its total time limit.',
          _skillScanTotalTimeout,
        );
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
              'Skill directory exceeds the $maxEntries entry scan limit.',
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
            'Skill directory exceeds the $_maxSkillScanDepth level depth limit.',
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

  Future<void> _deleteDirectoryIfExists(Directory directory) async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  Future<void> _deleteOptionalFileIfExists(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<Uint8List?> _readOptionalFileBytes(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
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
      if (await file.exists()) {
        await file.delete();
      }
      await deleteEmptyAncestorDirectories(
        start: file.parent,
        stopAt: Directory(rootDirectoryPath),
      );
      return;
    }

    final parentDirectory = file.parent;
    if (!await parentDirectory.exists()) {
      await parentDirectory.create(recursive: true);
    }
    await file.writeAsBytes(bytes, flush: true);
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

  final ArchiveFile file;
  final List<String> pathParts;
}

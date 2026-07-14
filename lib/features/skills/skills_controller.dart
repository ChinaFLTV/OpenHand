import 'package:flutter/foundation.dart';

import '../../shared/core/managed_change_notifier.dart';
import 'data/skills_repository.dart';
import 'model/local_skill.dart';

class SkillsController extends ManagedChangeNotifier {
  SkillsController._({
    required SkillsRepository repository,
    required String storagePath,
    bool isLoading = false,
  }) : _repository = repository,
       _storagePath = storagePath,
       _isLoading = isLoading;

  /// Constructs a [SkillsController] synchronously without performing the
  /// initial filesystem scan. Reports `isLoading == true` until the caller
  /// invokes [refresh] (typically as `unawaited(controller.refresh())`).
  ///
  /// Used by `main.dart` to keep the skills directory walk off the boot
  /// critical path — home reads `skills` only inside `_buildRuntimeContext`
  /// (user-action) and the workspace-selected branch (which observes
  /// [isLoading] for a placeholder).
  factory SkillsController.uninitialized({
    required String initialStoragePath,
    SkillsRepository? repository,
  }) {
    return SkillsController._(
      repository: repository ?? SkillsRepository(),
      storagePath: initialStoragePath,
      isLoading: true,
    );
  }

  static Future<SkillsController> create({
    required String initialStoragePath,
    SkillsRepository? repository,
  }) async {
    final controller = SkillsController._(
      repository: repository ?? SkillsRepository(),
      storagePath: initialStoragePath,
    );
    await controller.refresh();
    return controller;
  }

  final SkillsRepository _repository;

  String _storagePath;
  bool _isLoading;
  String? _errorMessage;
  List<LocalSkill> _skills = const <LocalSkill>[];

  String get storagePath => _storagePath;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<LocalSkill> get skills => List<LocalSkill>.unmodifiable(_skills);

  Future<void> refresh() async {
    await _enqueueOperation(_refreshLocked);
  }

  Future<bool> reloadFromPath(String storagePath) async {
    return _enqueueOperation(() async {
      final previousStoragePath = _storagePath;
      final previousSkills = List<LocalSkill>.from(_skills);
      final previousErrorMessage = _errorMessage;
      _storagePath = storagePath;
      await _refreshLocked();
      final reloadSucceeded = _errorMessage == null;
      if (_storagePath != previousStoragePath && !reloadSucceeded) {
        _storagePath = previousStoragePath;
        _skills = previousSkills;
        _errorMessage = previousErrorMessage;
        notifyListeners();
      }
      return reloadSucceeded;
    });
  }

  Future<LocalSkill> createSkillTemplate() async {
    return _enqueueOperation(() async {
      final skill = await _repository.createSkillTemplate(_storagePath);
      await _refreshLocked();
      return _findSkillByManifestPath(skill.manifestPath) ?? skill;
    });
  }

  Future<LocalSkill> createSkill({
    required String name,
    String? emojiIcon,
    Uint8List? imageIconBytes,
    required String shortDescription,
    required String manifestContent,
  }) async {
    return _enqueueOperation(() async {
      final skill = await _repository.createSkill(
        _storagePath,
        name: name,
        emojiIcon: emojiIcon,
        imageIconBytes: imageIconBytes,
        shortDescription: shortDescription,
        manifestContent: manifestContent,
      );
      await _refreshLocked();
      return _findSkillByManifestPath(skill.manifestPath) ?? skill;
    });
  }

  Future<LocalSkill> importSkillDirectory(String sourceDirectoryPath) async {
    return _enqueueOperation(() async {
      final skill = await _repository.importSkillDirectory(
        _storagePath,
        sourceDirectoryPath,
      );
      await _refreshLocked();
      return _findSkillByManifestPath(skill.manifestPath) ?? skill;
    });
  }

  Future<LocalSkill> installSkillArchive({
    required String preferredSlug,
    required Uint8List archiveBytes,
  }) async {
    return _enqueueOperation(() async {
      final skill = await _repository.installSkillArchive(
        _storagePath,
        preferredSlug: preferredSlug,
        archiveBytes: archiveBytes,
      );
      await _refreshLocked();
      return _findSkillByManifestPath(skill.manifestPath) ?? skill;
    });
  }

  Future<String> readSkillManifest(LocalSkill skill) {
    return _repository.readSkillManifest(skill);
  }

  Future<LocalSkill> updateSkillManifest(
    LocalSkill skill,
    String content,
  ) async {
    return _enqueueOperation(() async {
      final updatedSkill = await _repository.updateSkillManifest(
        skill,
        _storagePath,
        content,
      );
      await _refreshLocked();
      return _findSkillByManifestPath(updatedSkill.manifestPath) ??
          updatedSkill;
    });
  }

  Future<LocalSkill> updateSkill({
    required LocalSkill skill,
    required String name,
    String? emojiIcon,
    Uint8List? imageIconBytes,
    required String shortDescription,
    required String manifestContent,
    bool preserveExistingIcon = false,
  }) async {
    return _enqueueOperation(() async {
      final updatedSkill = await _repository.updateSkill(
        skill,
        _storagePath,
        name: name,
        emojiIcon: emojiIcon,
        imageIconBytes: imageIconBytes,
        shortDescription: shortDescription,
        manifestContent: manifestContent,
        preserveExistingIcon: preserveExistingIcon,
      );
      await _refreshLocked();
      return _findSkillByManifestPath(updatedSkill.manifestPath) ??
          updatedSkill;
    });
  }

  Future<void> deleteSkill(LocalSkill skill) async {
    await _enqueueOperation(() async {
      await _repository.deleteSkill(skill, _storagePath);
      await _refreshLocked();
    });
  }

  Future<void> _refreshLocked() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _skills = await _repository.loadInstalledSkills(_storagePath);
    } catch (error) {
      _skills = const <LocalSkill>[];
      _errorMessage = '$error';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> openStorageDirectory() {
    return _repository.openDirectory(_storagePath);
  }

  Future<void> openSkillDirectory(LocalSkill skill) {
    return _repository.openDirectory(skill.directoryPath);
  }

  LocalSkill? _findSkillByManifestPath(String manifestPath) {
    for (final skill in _skills) {
      if (skill.manifestPath == manifestPath) {
        return skill;
      }
    }
    return null;
  }

  Future<T> _enqueueOperation<T>(Future<T> Function() operation) {
    return enqueueOperation(operation);
  }
}

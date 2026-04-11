import 'dart:async';

import 'package:flutter/foundation.dart';

import 'data/skills_repository.dart';
import 'model/local_skill.dart';

class SkillsController extends ChangeNotifier {
  SkillsController._({
    required SkillsRepository repository,
    required String storagePath,
  }) : _repository = repository,
       _storagePath = storagePath;

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
  bool _isLoading = false;
  String? _errorMessage;
  List<LocalSkill> _skills = const <LocalSkill>[];
  bool _isDisposed = false;
  Future<void> _operationQueue = Future<void>.value();

  String get storagePath => _storagePath;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<LocalSkill> get skills => List<LocalSkill>.unmodifiable(_skills);
  int get installedCount => _skills.length;

  @override
  void notifyListeners() {
    if (_isDisposed) {
      return;
    }
    super.notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

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
    if (_isDisposed) {
      return Future<T>.error(StateError('SkillsController is disposed'));
    }
    final completer = Completer<T>();
    _operationQueue = _operationQueue.catchError((_) {}).then((_) async {
      // Check disposed state before executing to avoid race conditions.
      if (_isDisposed) {
        if (!completer.isCompleted) {
          completer.completeError(StateError('SkillsController is disposed'));
        }
        return;
      }
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      }
    });
    return completer.future;
  }
}

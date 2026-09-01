import 'package:flutter/foundation.dart';

import '../../app/support/silent_log.dart';
import '../../shared/core/managed_change_notifier.dart';
import '../../shared/util/user_failure_message.dart';
import 'data/skills_repository.dart';
import 'model/local_skill.dart';

class SkillsController extends ManagedChangeNotifier {
  SkillsController._({
    required this._repository,
    required this._storagePath,
    this._isLoading = false,
  });

  /// 同步创建控制器，不立即扫描文件系统。调用方执行 [refresh] 前，
  /// `isLoading` 保持为 `true`。
  ///
  /// 用于让 `main.dart` 避免在启动关键路径遍历技能目录；首页仅在构建
  /// 运行时上下文或选择工作区后读取技能列表。
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

  final SkillsRepository _repository;

  String _storagePath;
  bool _isLoading;
  String? _errorMessage;
  List<LocalSkill> _skills = const <LocalSkill>[];
  List<LocalSkill> _skillsView = const <LocalSkill>[];

  String get storagePath => _storagePath;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<LocalSkill> get skills => _skillsView;

  Future<void> refresh() async {
    await _enqueueOperation(_refreshLocked);
  }

  Future<bool> reloadFromPath(String storagePath) async {
    return _enqueueOperation(() async {
      final previousStoragePath = _storagePath;
      _storagePath = storagePath;
      await _refreshLocked();
      final reloadSucceeded = _errorMessage == null;
      if (_storagePath != previousStoragePath && !reloadSucceeded) {
        _storagePath = previousStoragePath;
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
      _setSkills(await _repository.loadInstalledSkills(_storagePath));
    } catch (error, stack) {
      silentLog('skills_controller', '加载技能', error, stack);
      _errorMessage = userFailureMessage(error, fallback: '技能加载失败，请稍后重试。');
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

  void _setSkills(List<LocalSkill> skills) {
    _skills = skills;
    _skillsView = List<LocalSkill>.unmodifiable(skills);
  }

  Future<T> _enqueueOperation<T>(Future<T> Function() operation) {
    return enqueueOperation(operation);
  }
}

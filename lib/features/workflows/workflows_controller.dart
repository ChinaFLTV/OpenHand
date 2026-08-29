import 'package:flutter/foundation.dart';

import '../../app/support/silent_log.dart';
import '../../shared/core/managed_change_notifier.dart';
import '../../shared/util/user_failure_message.dart';
import 'data/workflows_store.dart';
import 'model/workflow_definition.dart';

class WorkflowsController extends ManagedChangeNotifier {
  WorkflowsController._(this._store);

  static Future<WorkflowsController> create({WorkflowsStore? store}) async {
    final controller = WorkflowsController._(store ?? WorkflowsStore());
    await controller.refresh();
    return controller;
  }

  final WorkflowsStore _store;
  List<WorkflowDefinition> _workflows = const <WorkflowDefinition>[];
  bool _isLoading = true;
  bool _hasTrustedSnapshot = false;
  String? _errorMessage;
  final ChangePulse _saveSuccessPulse = ChangePulse();

  List<WorkflowDefinition> get workflows => _workflows;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  ValueListenable<int> get saveSuccessSignal => _saveSuccessPulse.listenable;

  @override
  void dispose() {
    _saveSuccessPulse.dispose();
    super.dispose();
  }

  Future<void> refresh() => enqueueOperation(_loadLocked);

  Future<bool> save(WorkflowDefinition workflow) {
    return enqueueOperation(() async {
      if (!await _ensureTrustedSnapshotLocked()) return false;
      final normalizedName = workflow.name.trim();
      if (workflow.id.trim().isEmpty || normalizedName.isEmpty) {
        _errorMessage = '工作流名称不能为空。';
        notifyListeners();
        return false;
      }
      final now = DateTime.now().toUtc();
      final nextWorkflow = workflow.copyWith(
        name: normalizedName,
        updatedAt: now,
      );
      final next = <WorkflowDefinition>[
        nextWorkflow,
        ..._workflows.where((item) => item.id != nextWorkflow.id),
      ];
      return _commit('保存工作流', next, () => _store.save(nextWorkflow));
    });
  }

  Future<bool> delete(String id) {
    final normalizedId = id.trim();
    if (normalizedId.isEmpty) return Future<bool>.value(false);
    return enqueueOperation(() async {
      if (!await _ensureTrustedSnapshotLocked()) return false;
      if (!_workflows.any((item) => item.id == normalizedId)) return false;
      final next = _workflows
          .where((item) => item.id != normalizedId)
          .toList(growable: false);
      return _commit('删除工作流', next, () => _store.delete(normalizedId));
    });
  }

  Future<bool> _commit(
    String action,
    List<WorkflowDefinition> next,
    Future<void> Function() persist,
  ) async {
    final previous = _workflows;
    _errorMessage = null;
    try {
      await persist();
      _workflows = List<WorkflowDefinition>.unmodifiable(next);
      _hasTrustedSnapshot = true;
      _saveSuccessPulse.emit();
      notifyListeners();
      return true;
    } catch (error, stack) {
      silentLog('workflows_controller', action, error, stack);
      _workflows = previous;
      _errorMessage = userFailureMessage(error, fallback: '$action失败，请稍后重试。');
      notifyListeners();
      return false;
    }
  }

  Future<void> _loadLocked() async {
    final hadTrustedSnapshot = _hasTrustedSnapshot;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _store.ensureTable();
      _workflows = List<WorkflowDefinition>.unmodifiable(
        await _store.loadAll(),
      );
      _hasTrustedSnapshot = true;
    } catch (error, stack) {
      silentLog('workflows_controller', '加载工作流', error, stack);
      _hasTrustedSnapshot = hadTrustedSnapshot;
      _errorMessage = userFailureMessage(error, fallback: '加载工作流失败，请稍后重试。');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> _ensureTrustedSnapshotLocked() async {
    if (_hasTrustedSnapshot) return true;
    await _loadLocked();
    return _hasTrustedSnapshot;
  }
}

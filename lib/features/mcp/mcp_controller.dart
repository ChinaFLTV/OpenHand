import 'dart:async';

import 'package:flutter/foundation.dart';

import 'data/mcp_store.dart';
import 'model/mcp_server.dart';

class McpController extends ChangeNotifier {
  McpController._({required McpStore store}) : _store = store;

  static Future<McpController> create({
    required String initialFilePath,
    McpStore? store,
  }) async {
    final controller = McpController._(
      store: store ?? McpStore(serversFilePath: initialFilePath),
    );
    await controller.refresh();
    return controller;
  }

  final McpStore _store;

  bool _isLoading = false;
  String? _errorMessage;
  List<McpServer> _servers = const <McpServer>[];
  McpPersistenceIssue? _persistenceIssue;
  Future<void> _operationQueue = Future<void>.value();

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<McpServer> get servers => List<McpServer>.unmodifiable(_servers);
  String get serversFilePath => _store.serversFilePath;
  String get storageDirectoryPath => _store.storageDirectoryPath;
  McpPersistenceIssue? get persistenceIssue => _persistenceIssue;

  void clearPersistenceIssue() {
    if (_persistenceIssue == null) {
      return;
    }
    _persistenceIssue = null;
    notifyListeners();
  }

  Future<void> refresh() async {
    await _enqueueOperation(() async {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      try {
        final loadResult = await _store.load();
        _servers = loadResult.servers;
        _persistenceIssue = loadResult.issue;
      } catch (error) {
        _servers = const <McpServer>[];
        _errorMessage = '$error';
      } finally {
        _isLoading = false;
        notifyListeners();
      }
    });
  }

  Future<bool> saveServer(McpServer server, {String? previousName}) async {
    final normalizedName = server.name.trim();
    if (normalizedName.isEmpty) {
      return false;
    }
    return _enqueueOperation(() async {
      final updatedServers = List<McpServer>.from(_servers);
      final normalizedPreviousName = previousName?.trim();
      if (normalizedPreviousName != null && normalizedPreviousName.isNotEmpty) {
        updatedServers.removeWhere(
          (item) => item.name == normalizedPreviousName,
        );
      }
      final duplicateExists = updatedServers.any(
        (item) => item.name == normalizedName,
      );
      if (duplicateExists) {
        return false;
      }
      updatedServers.add(server.copyWith(name: normalizedName));
      updatedServers.sort(
        (left, right) =>
            left.name.toLowerCase().compareTo(right.name.toLowerCase()),
      );
      return _commitSaveLocked(updatedServers);
    });
  }

  Future<bool> deleteServer(McpServer server) async {
    return _enqueueOperation(() async {
      final updatedServers = _servers
          .where((item) => item.name != server.name)
          .toList(growable: false);
      if (updatedServers.length == _servers.length) {
        return true;
      }
      return _commitSaveLocked(updatedServers);
    });
  }

  Future<bool> updateServerEnabled(String name, bool enabled) async {
    return _enqueueOperation(() async {
      final index = _servers.indexWhere((item) => item.name == name);
      if (index == -1) {
        return false;
      }
      if (_servers[index].enabled == enabled) {
        return true;
      }

      final updatedServers = List<McpServer>.from(_servers);
      updatedServers[index] = updatedServers[index].copyWith(enabled: enabled);
      return _commitSaveLocked(updatedServers);
    });
  }

  Future<void> openStorageDirectory() {
    return _store.openStorageDirectory();
  }

  Future<bool> _commitSaveLocked(List<McpServer> nextServers) async {
    final previousServers = List<McpServer>.from(_servers);
    _servers = nextServers;
    _errorMessage = null;
    notifyListeners();
    try {
      await _store.save(nextServers);
      if (_persistenceIssue != null) {
        _persistenceIssue = null;
        notifyListeners();
      }
      return true;
    } catch (error) {
      _servers = previousServers;
      _persistenceIssue = McpPersistenceIssue(
        kind: McpPersistenceIssueKind.saveFailed,
        filePath: _store.serversFilePath,
        detail: '$error',
      );
      notifyListeners();
      return false;
    }
  }

  Future<T> _enqueueOperation<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _operationQueue = _operationQueue.catchError((_) {}).then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}

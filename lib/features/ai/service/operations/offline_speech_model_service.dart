import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../../app/support/openhand_paths.dart';
import '../../../../app/support/safe_subprocess.dart';
import '../../../../app/support/system_proxy.dart';
import '../../model/offline_speech_model.dart';

enum OfflineSpeechLifecycle {
  absent,
  downloading,
  installed,
  starting,
  running,
  stopping,
  failed,
}

class OfflineSpeechModelState {
  const OfflineSpeechModelState({
    required this.lifecycle,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.bytesPerSecond = 0,
    this.completedFiles = 0,
    this.totalFiles = 0,
    this.message,
  });

  final OfflineSpeechLifecycle lifecycle;
  final int receivedBytes;
  final int totalBytes;
  final double bytesPerSecond;
  final int completedFiles;
  final int totalFiles;
  final String? message;

  double? get progress => totalBytes > 0
      ? (receivedBytes / totalBytes).clamp(0, 1)
      : totalFiles > 0
      ? (completedFiles / totalFiles).clamp(0, 1)
      : null;
}

class OfflineSpeechDownloadCancelled implements Exception {
  const OfflineSpeechDownloadCancelled();
}

class OfflineSpeechHardwareProfile {
  const OfflineSpeechHardwareProfile({
    required this.platformSupported,
    required this.architecture,
    required this.logicalCores,
    required this.totalMemoryBytes,
    required this.freeStorageBytes,
  });

  final bool platformSupported;
  final String architecture;
  final int logicalCores;
  final int totalMemoryBytes;
  final int freeStorageBytes;
}

class OfflineSpeechModelAvailability {
  const OfflineSpeechModelAvailability({
    required this.available,
    required this.reason,
  });

  final bool available;
  final String reason;
}

abstract interface class OfflineSpeechRuntimeAdapter {
  Future<Process> start({
    required String pythonExecutable,
    required String runnerPath,
    required OfflineSpeechModelDefinition model,
    required String modelPath,
    required Map<String, Object?> configuration,
  });
}

class PythonOfflineSpeechRuntimeAdapter implements OfflineSpeechRuntimeAdapter {
  const PythonOfflineSpeechRuntimeAdapter(this.runtime);

  final OfflineSpeechRuntime runtime;

  @override
  Future<Process> start({
    required String pythonExecutable,
    required String runnerPath,
    required OfflineSpeechModelDefinition model,
    required String modelPath,
    required Map<String, Object?> configuration,
  }) {
    if (model.runtime != runtime) {
      throw StateError('模型运行时适配器不匹配。');
    }
    return startTrackedProcessBounded(
      pythonExecutable,
      <String>[
        '-u',
        runnerPath,
        '--runtime',
        runtime.name,
        '--model',
        modelPath,
        '--config',
        base64Url.encode(utf8.encode(jsonEncode(configuration))),
      ],
      timeout: const Duration(seconds: 15),
      tag: 'offline_speech.start.${runtime.name}',
    );
  }
}

class OfflineSpeechModelService extends ChangeNotifier {
  OfflineSpeechModelService._() {
    unawaited(_inspectHardware());
  }

  static final OfflineSpeechModelService instance =
      OfflineSpeechModelService._();
  static const Duration _runtimeStartTimeout = Duration(minutes: 3);
  static const Duration _downloadNotifyInterval = Duration(milliseconds: 80);
  static const Set<String> _metadataExtensions = <String>{
    '.json',
    '.txt',
    '.model',
    '.tiktoken',
    '.yaml',
    '.yml',
    '.py',
    '.fst',
    '.tokens',
    '.lexicon',
    '.vocab',
    '.mvn',
  };
  static const Set<String> _weightExtensions = <String>{
    '.safetensors',
    '.pt',
    '.pth',
    '.onnx',
    '.gguf',
    '.bin',
    '.npz',
    '.npy',
  };

  final Map<String, OfflineSpeechModelState> _states =
      <String, OfflineSpeechModelState>{};
  final Map<String, _DownloadCancellation> _downloadCancellations =
      <String, _DownloadCancellation>{};
  final Map<String, Process> _processes = <String, Process>{};
  OfflineSpeechHardwareProfile? _hardwareProfile;
  final Map<OfflineSpeechRuntime, OfflineSpeechRuntimeAdapter>
  _runtimeAdapters = <OfflineSpeechRuntime, OfflineSpeechRuntimeAdapter>{
    for (final runtime in OfflineSpeechRuntime.values)
      runtime: PythonOfflineSpeechRuntimeAdapter(runtime),
  };

  String get modelsRoot =>
      p.join(OpenHandPaths.defaultRootDirectoryPath(), 'models', 'speech');

  OfflineSpeechHardwareProfile? get hardwareProfile => _hardwareProfile;

  OfflineSpeechModelAvailability availabilityFor(
    OfflineSpeechModelDefinition model,
    Map<String, Object?> configuration,
  ) {
    final profile = _hardwareProfile;
    if (profile == null) {
      return const OfflineSpeechModelAvailability(
        available: false,
        reason: '正在评估设备配置…',
      );
    }
    if (!profile.platformSupported) {
      return const OfflineSpeechModelAvailability(
        available: false,
        reason: '本地语音模型当前支持 macOS、Windows 和 Linux 桌面端。',
      );
    }
    if (!const <String>{'arm64', 'x64'}.contains(profile.architecture)) {
      return OfflineSpeechModelAvailability(
        available: false,
        reason: '不支持当前 ${profile.architecture} 处理器架构。',
      );
    }
    if (profile.totalMemoryBytes <= 0) {
      return const OfflineSpeechModelAvailability(
        available: false,
        reason: '无法读取设备物理内存。',
      );
    }
    if (profile.freeStorageBytes <= 0) {
      return const OfflineSpeechModelAvailability(
        available: false,
        reason: '无法读取模型目录的可用空间。',
      );
    }
    final requirement = _hardwareRequirement(model, configuration);
    final currentMemoryGiB = profile.totalMemoryBytes / (1024 * 1024 * 1024);
    if (currentMemoryGiB < requirement.memoryGiB) {
      return OfflineSpeechModelAvailability(
        available: false,
        reason:
            '至少需要 ${requirement.memoryGiB} GB 内存，当前约 ${currentMemoryGiB.toStringAsFixed(1)} GB。',
      );
    }
    if (profile.logicalCores < requirement.logicalCores) {
      return OfflineSpeechModelAvailability(
        available: false,
        reason:
            '至少需要 ${requirement.logicalCores} 个逻辑核心，当前为 ${profile.logicalCores} 个。',
      );
    }
    final freeStorageGiB = profile.freeStorageBytes / (1024 * 1024 * 1024);
    if (freeStorageGiB < requirement.storageGiB) {
      return OfflineSpeechModelAvailability(
        available: false,
        reason:
            '至少需要 ${requirement.storageGiB.toStringAsFixed(1)} GB 可用空间，当前约 ${freeStorageGiB.toStringAsFixed(1)} GB。',
      );
    }
    return OfflineSpeechModelAvailability(
      available: true,
      reason:
          '设备满足 ${requirement.memoryGiB} GB 内存、${requirement.logicalCores} 核和 ${requirement.storageGiB.toStringAsFixed(1)} GB 空间要求。',
    );
  }

  String modelDirectory(OfflineSpeechModelDefinition model) =>
      p.join(modelsRoot, model.id);

  OfflineSpeechModelState stateOf(OfflineSpeechModelDefinition model) {
    final current = _states[model.id];
    if (current != null) return current;
    return OfflineSpeechModelState(
      lifecycle:
          File(
            p.join(modelDirectory(model), 'openhand-model.json'),
          ).existsSync()
          ? OfflineSpeechLifecycle.installed
          : OfflineSpeechLifecycle.absent,
    );
  }

  bool isInstalled(OfflineSpeechModelDefinition model) {
    return File(
      p.join(modelDirectory(model), 'openhand-model.json'),
    ).existsSync();
  }

  bool requiresDownloadForConfiguration(
    OfflineSpeechModelDefinition model,
    Map<String, Object?> configuration,
  ) {
    final manifest = File(p.join(modelDirectory(model), 'openhand-model.json'));
    if (!manifest.existsSync()) return true;
    final expected = _artifactConfiguration(model, configuration);
    if (expected.isEmpty) return false;
    try {
      final payload = jsonDecode(manifest.readAsStringSync());
      if (payload is! Map || payload['artifact_configuration'] is! Map) {
        return true;
      }
      final installed = Map<String, Object?>.from(
        payload['artifact_configuration'] as Map,
      );
      return jsonEncode(installed) != jsonEncode(expected);
    } catch (_) {
      return true;
    }
  }

  Future<void> download(
    OfflineSpeechModelDefinition model,
    Map<String, Object?> configuration,
  ) async {
    if (_downloadCancellations.containsKey(model.id)) return;
    await _inspectHardware();
    final availability = availabilityFor(model, configuration);
    if (!availability.available) throw StateError(availability.reason);
    final target = Directory(modelDirectory(model));
    final staging = Directory('${target.path}.partial');
    final cancellation = _DownloadCancellation();
    _downloadCancellations[model.id] = cancellation;
    _setState(
      model.id,
      const OfflineSpeechModelState(
        lifecycle: OfflineSpeechLifecycle.downloading,
      ),
    );
    try {
      if (await staging.exists()) await staging.delete(recursive: true);
      await staging.create(recursive: true);
      final files = await _loadRepositoryFiles(
        model,
        configuration,
        cancellation,
      );
      if (files.isEmpty) throw StateError('模型仓库没有可下载的运行文件。');
      final totalBytes = files.fold<int>(0, (sum, file) => sum + file.size);
      var receivedBytes = 0;
      var completedFiles = 0;
      final stopwatch = Stopwatch()..start();
      var lastNotified = Duration.zero;
      for (final remote in files) {
        cancellation.throwIfCancelled();
        final file = File(p.join(staging.path, remote.path));
        await file.parent.create(recursive: true);
        final sink = file.openWrite();
        var fileBytes = 0;
        try {
          final opened = await _openDownload(remote.uri, cancellation);
          try {
            await for (final chunk in opened.response) {
              cancellation.throwIfCancelled();
              sink.add(chunk);
              fileBytes += chunk.length;
              receivedBytes += chunk.length;
              final elapsed = stopwatch.elapsed;
              if (elapsed - lastNotified >= _downloadNotifyInterval) {
                lastNotified = elapsed;
                _setState(
                  model.id,
                  OfflineSpeechModelState(
                    lifecycle: OfflineSpeechLifecycle.downloading,
                    receivedBytes: receivedBytes,
                    totalBytes: totalBytes,
                    bytesPerSecond: elapsed.inMilliseconds == 0
                        ? 0
                        : receivedBytes * 1000 / elapsed.inMilliseconds,
                    completedFiles: completedFiles,
                    totalFiles: files.length,
                    message: remote.path,
                  ),
                );
              }
            }
          } finally {
            if (identical(cancellation.client, opened.client)) {
              cancellation.client = null;
            }
            opened.client.close(force: cancellation.cancelled);
          }
        } finally {
          await sink.flush();
          await sink.close();
        }
        if (remote.size > 0 && fileBytes != remote.size) {
          throw StateError('模型文件下载不完整：${remote.path}');
        }
        completedFiles++;
      }
      cancellation.throwIfCancelled();
      await File(p.join(staging.path, 'openhand-model.json')).writeAsString(
        const JsonEncoder.withIndent('  ').convert(<String, Object?>{
          'id': model.id,
          'repository': _repositoryFor(model, configuration),
          'downloaded_at': DateTime.now().toUtc().toIso8601String(),
          'artifact_configuration': _artifactConfiguration(
            model,
            configuration,
          ),
          'files': files.map((file) => file.path).toList(growable: false),
        }),
        flush: true,
      );
      if (await target.exists()) await target.delete(recursive: true);
      await staging.rename(target.path);
      _setState(
        model.id,
        OfflineSpeechModelState(
          lifecycle: OfflineSpeechLifecycle.installed,
          receivedBytes: receivedBytes,
          totalBytes: math.max(totalBytes, receivedBytes),
          completedFiles: files.length,
          totalFiles: files.length,
          message: '下载完成',
        ),
      );
      unawaited(_inspectHardware());
    } catch (error) {
      if (await staging.exists()) await staging.delete(recursive: true);
      final retained = File(
        p.join(target.path, 'openhand-model.json'),
      ).existsSync();
      if (cancellation.cancelled || error is OfflineSpeechDownloadCancelled) {
        _setState(
          model.id,
          OfflineSpeechModelState(
            lifecycle: retained
                ? OfflineSpeechLifecycle.installed
                : OfflineSpeechLifecycle.absent,
          ),
        );
        throw const OfflineSpeechDownloadCancelled();
      }
      _setState(
        model.id,
        OfflineSpeechModelState(
          lifecycle: retained
              ? OfflineSpeechLifecycle.installed
              : OfflineSpeechLifecycle.failed,
          message: '$error',
        ),
      );
      rethrow;
    } finally {
      cancellation.close();
      _downloadCancellations.remove(model.id);
    }
  }

  void cancelDownload(OfflineSpeechModelDefinition model) {
    _downloadCancellations[model.id]?.cancel();
  }

  Future<void> remove(OfflineSpeechModelDefinition model) async {
    cancelDownload(model);
    await stop(model);
    final target = Directory(modelDirectory(model));
    final staging = Directory('${target.path}.partial');
    if (await target.exists()) await target.delete(recursive: true);
    if (await staging.exists()) await staging.delete(recursive: true);
    _setState(
      model.id,
      const OfflineSpeechModelState(lifecycle: OfflineSpeechLifecycle.absent),
    );
    unawaited(_inspectHardware());
  }

  Future<void> start(
    OfflineSpeechModelDefinition model,
    Map<String, Object?> configuration,
  ) async {
    await _inspectHardware();
    final availability = availabilityFor(model, configuration);
    if (!availability.available) throw StateError(availability.reason);
    if (!isInstalled(model)) throw StateError('请先下载模型。');
    if (requiresDownloadForConfiguration(model, configuration)) {
      throw StateError('模型尺寸或精度已经变更，请重新下载当前配置。');
    }
    if (_processes.containsKey(model.id)) return;
    final runningSameKind = _processes.keys
        .map(OfflineSpeechModelCatalog.byId)
        .whereType<OfflineSpeechModelDefinition>()
        .where((candidate) => candidate.kind == model.kind)
        .toList(growable: false);
    for (final candidate in runningSameKind) {
      await stop(candidate);
    }
    _setState(
      model.id,
      const OfflineSpeechModelState(lifecycle: OfflineSpeechLifecycle.starting),
    );
    Process? process;
    try {
      final python =
          _findExecutable(Platform.isWindows ? 'python.exe' : 'python3') ??
          _findExecutable('python');
      if (python == null) throw StateError('未检测到 Python 3，无法启动模型运行时。');
      final runner = await _writeRuntimeHost();
      process = await _runtimeAdapters[model.runtime]!.start(
        pythonExecutable: python,
        runnerPath: runner.path,
        model: model,
        modelPath: modelDirectory(model),
        configuration: configuration,
      );
      _processes[model.id] = process;
      final ready = Completer<void>();
      final errors = StringBuffer();
      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            if (line == 'OPENHAND_模型就绪' && !ready.isCompleted) {
              ready.complete();
            }
          });
      process.stderr.transform(utf8.decoder).listen((line) {
        if (errors.length < 8000) errors.write(line);
      });
      unawaited(
        process.exitCode.then((code) {
          if (!ready.isCompleted) {
            ready.completeError(
              StateError(
                errors.toString().trim().isEmpty
                    ? '模型运行时异常退出（$code）。'
                    : errors.toString().trim(),
              ),
            );
          }
          if (identical(_processes[model.id], process)) {
            _processes.remove(model.id);
            _setState(
              model.id,
              OfflineSpeechModelState(
                lifecycle: OfflineSpeechLifecycle.failed,
                message: '模型运行时已退出（$code）',
              ),
            );
          }
        }),
      );
      await ready.future.timeout(_runtimeStartTimeout);
      _setState(
        model.id,
        const OfflineSpeechModelState(
          lifecycle: OfflineSpeechLifecycle.running,
        ),
      );
    } catch (error) {
      _processes.remove(model.id);
      process?.kill(ProcessSignal.sigkill);
      _setState(
        model.id,
        OfflineSpeechModelState(
          lifecycle: OfflineSpeechLifecycle.failed,
          message: '$error',
        ),
      );
      rethrow;
    }
  }

  Future<void> stop(OfflineSpeechModelDefinition model) async {
    final process = _processes.remove(model.id);
    if (process == null) {
      if (isInstalled(model)) {
        _setState(
          model.id,
          const OfflineSpeechModelState(
            lifecycle: OfflineSpeechLifecycle.installed,
          ),
        );
      }
      return;
    }
    _setState(
      model.id,
      const OfflineSpeechModelState(lifecycle: OfflineSpeechLifecycle.stopping),
    );
    process.kill();
    try {
      await process.exitCode.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
    }
    _setState(
      model.id,
      const OfflineSpeechModelState(
        lifecycle: OfflineSpeechLifecycle.installed,
      ),
    );
  }

  Future<void> test(
    OfflineSpeechModelDefinition model,
    Map<String, Object?> configuration,
  ) async {
    final wasRunning =
        stateOf(model).lifecycle == OfflineSpeechLifecycle.running;
    if (!wasRunning) await start(model, configuration);
    if (!wasRunning) await stop(model);
  }

  Future<List<_RemoteModelFile>> _loadRepositoryFiles(
    OfflineSpeechModelDefinition model,
    Map<String, Object?> configuration,
    _DownloadCancellation cancellation,
  ) async {
    final repository = _repositoryFor(model, configuration);
    final uri = Uri.https(
      'huggingface.co',
      '/api/models/$repository',
      <String, String>{'blobs': 'true'},
    );
    final client = SystemProxyResolver.instance.createRawHttpClient(
      connectionTimeout: const Duration(seconds: 30),
    );
    cancellation.client = client;
    try {
      final request = await client.getUrl(uri);
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'OpenHand offline speech manager',
      );
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          '读取模型文件清单失败（HTTP ${response.statusCode}）',
          uri: uri,
        );
      }
      final payload = jsonDecode(await utf8.decodeStream(response));
      if (payload is! Map || payload['siblings'] is! List) {
        return const <_RemoteModelFile>[];
      }
      final candidates = <_RemoteModelFile>[];
      for (final item in payload['siblings'] as List) {
        if (item is! Map) continue;
        final path = '${item['rfilename'] ?? ''}'.trim();
        if (!_shouldDownload(model, path)) continue;
        final lfs = item['lfs'];
        final size = lfs is Map && lfs['size'] is num
            ? (lfs['size'] as num).toInt()
            : item['size'] is num
            ? (item['size'] as num).toInt()
            : 0;
        candidates.add(
          _RemoteModelFile(
            path: path,
            size: size,
            uri: Uri(
              scheme: 'https',
              host: 'huggingface.co',
              pathSegments: <String>[
                ...repository.split('/'),
                'resolve',
                'main',
                ...path.split('/'),
              ],
            ),
          ),
        );
      }
      final hasSafetensors = candidates.any(
        (file) => file.path.endsWith('.safetensors'),
      );
      return candidates
          .where((file) {
            if (!hasSafetensors) return true;
            final name = p.basename(file.path).toLowerCase();
            return !(name.startsWith('pytorch_model') && name.endsWith('.bin'));
          })
          .where((file) => _matchesModelArtifact(model, file.path))
          .toList(growable: false);
    } finally {
      if (identical(cancellation.client, client)) cancellation.client = null;
      client.close(force: cancellation.cancelled);
    }
  }

  Future<void> _inspectHardware() async {
    if (kIsWeb || Platform.isAndroid || Platform.isIOS) {
      _hardwareProfile = OfflineSpeechHardwareProfile(
        platformSupported: false,
        architecture: 'unsupported',
        logicalCores: kIsWeb ? 0 : Platform.numberOfProcessors,
        totalMemoryBytes: 0,
        freeStorageBytes: 0,
      );
      notifyListeners();
      return;
    }
    final architecture = await _readArchitecture();
    final totalMemoryBytes = await _readTotalMemoryBytes();
    final freeStorageBytes = await _readFreeStorageBytes();
    _hardwareProfile = OfflineSpeechHardwareProfile(
      platformSupported: true,
      architecture: architecture,
      logicalCores: Platform.numberOfProcessors,
      totalMemoryBytes: totalMemoryBytes,
      freeStorageBytes: freeStorageBytes,
    );
    notifyListeners();
  }

  Future<String> _readArchitecture() async {
    if (Platform.isWindows) {
      final value = Platform.environment['PROCESSOR_ARCHITECTURE'] ?? '';
      return _normalizeArchitecture(value);
    }
    if (Platform.isMacOS) {
      final arm = await runTrackedProcessOrFailed('sysctl', const <String>[
        '-n',
        'hw.optional.arm64',
      ], tag: 'offline_speech.hardware.architecture');
      if ('${arm.stdout}'.trim() == '1') return 'arm64';
    }
    final result = await runTrackedProcessOrFailed('uname', const <String>[
      '-m',
    ], tag: 'offline_speech.hardware.architecture');
    return _normalizeArchitecture('${result.stdout}');
  }

  Future<int> _readTotalMemoryBytes() async {
    if (Platform.isMacOS) {
      final result = await runTrackedProcessOrFailed('sysctl', const <String>[
        '-n',
        'hw.memsize',
      ], tag: 'offline_speech.hardware.memory');
      return int.tryParse('${result.stdout}'.trim()) ?? 0;
    }
    if (Platform.isLinux) {
      try {
        final content = await File('/proc/meminfo').readAsString();
        final match = RegExp(
          r'^MemTotal:\s+(\d+)\s+kB$',
          multiLine: true,
        ).firstMatch(content);
        return (int.tryParse(match?.group(1) ?? '') ?? 0) * 1024;
      } catch (_) {
        return 0;
      }
    }
    final result =
        await runTrackedProcessOrFailed('powershell.exe', const <String>[
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          '(Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory',
        ], tag: 'offline_speech.hardware.memory');
    return int.tryParse('${result.stdout}'.trim()) ?? 0;
  }

  Future<int> _readFreeStorageBytes() async {
    if (Platform.isWindows) {
      final root = p.rootPrefix(modelsRoot).replaceAll("'", "''");
      final result = await runTrackedProcessOrFailed('powershell.exe', <String>[
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        "([IO.DriveInfo]::new('$root')).AvailableFreeSpace",
      ], tag: 'offline_speech.hardware.storage');
      return int.tryParse('${result.stdout}'.trim()) ?? 0;
    }
    final result = await runTrackedProcessOrFailed('df', <String>[
      '-Pk',
      OpenHandPaths.homeDirectoryPath(),
    ], tag: 'offline_speech.hardware.storage');
    final lines = '${result.stdout}'
        .trim()
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList(growable: false);
    if (lines.length < 2) return 0;
    final columns = lines.last.trim().split(RegExp(r'\s+'));
    return columns.length > 3 ? (int.tryParse(columns[3]) ?? 0) * 1024 : 0;
  }

  static String _normalizeArchitecture(String raw) {
    final value = raw.trim().toLowerCase();
    if (value == 'arm64' || value == 'aarch64') return 'arm64';
    if (value == 'x86_64' || value == 'amd64') return 'x64';
    return value.isEmpty ? 'unknown' : value;
  }

  static ({int memoryGiB, int logicalCores, double storageGiB})
  _hardwareRequirement(
    OfflineSpeechModelDefinition model,
    Map<String, Object?> configuration,
  ) {
    if (model.id == 'whisper') {
      return switch (configuration['model']) {
        'tiny' => (memoryGiB: 2, logicalCores: 2, storageGiB: 0.2),
        'base' => (memoryGiB: 3, logicalCores: 2, storageGiB: 0.4),
        'medium' => (memoryGiB: 8, logicalCores: 4, storageGiB: 2.0),
        'large-v3-turbo' => (memoryGiB: 10, logicalCores: 6, storageGiB: 3.5),
        _ => (memoryGiB: 4, logicalCores: 4, storageGiB: 1.0),
      };
    }
    return switch (model.id) {
      'zipformer-zh-en' => (memoryGiB: 2, logicalCores: 2, storageGiB: 0.7),
      'kokoro-82m' => (
        memoryGiB: 2,
        logicalCores: 2,
        storageGiB: configuration['quantization'] == 'fp32' ? 0.5 : 0.3,
      ),
      'sensevoice-small' || 'paraformer-zh-streaming' => (
        memoryGiB: 4,
        logicalCores: 4,
        storageGiB: 1.2,
      ),
      'qwen3-asr-0.6b' ||
      'qwen3-tts-0.6b-custom' ||
      'qwen3-tts-0.6b-base' => (memoryGiB: 8, logicalCores: 4, storageGiB: 2.5),
      'qwen3-asr-1.7b' ||
      'qwen3-tts-1.7b-custom' ||
      'qwen3-tts-1.7b-base' ||
      'qwen3-tts-1.7b-design' => (
        memoryGiB: 12,
        logicalCores: 6,
        storageGiB: 5.0,
      ),
      'fun-asr-nano' ||
      'fun-asr-mlt-nano' => (memoryGiB: 8, logicalCores: 4, storageGiB: 3.0),
      'cosyvoice3-0.5b' => (memoryGiB: 10, logicalCores: 6, storageGiB: 5.0),
      _ => (memoryGiB: 4, logicalCores: 4, storageGiB: 1.0),
    };
  }

  Future<({HttpClientResponse response, HttpClient client})> _openDownload(
    Uri uri,
    _DownloadCancellation cancellation,
  ) async {
    final client = SystemProxyResolver.instance.createRawHttpClient(
      connectionTimeout: const Duration(seconds: 30),
    );
    cancellation.client = client;
    final request = await client.getUrl(uri);
    request.headers.set(
      HttpHeaders.userAgentHeader,
      'OpenHand offline speech manager',
    );
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      client.close(force: true);
      throw HttpException('下载失败（HTTP ${response.statusCode}）', uri: uri);
    }
    return (response: response, client: client);
  }

  static bool _shouldDownload(OfflineSpeechModelDefinition model, String path) {
    if (path.isEmpty || p.isAbsolute(path) || path.split('/').contains('..')) {
      return false;
    }
    final lower = path.toLowerCase();
    if (lower.startsWith('.') ||
        lower.contains('/docs/') ||
        lower.contains('/examples/') ||
        lower.contains('/samples/') ||
        lower.contains('/assets/') ||
        lower.endsWith('readme.md') ||
        lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.wav') ||
        lower.endsWith('.mp3') ||
        lower.endsWith('.pdf')) {
      return false;
    }
    if (model.id == 'kokoro-82m') return true;
    final extension = p.extension(lower);
    return extension.isEmpty ||
        _weightExtensions.contains(extension) ||
        _metadataExtensions.contains(extension) ||
        p.basename(lower).startsWith('license');
  }

  static bool _matchesModelArtifact(
    OfflineSpeechModelDefinition model,
    String path,
  ) {
    final lower = path.toLowerCase();
    if (model.id == 'cosyvoice3-0.5b') {
      if (lower == 'llm.rl.pt' || lower == 'flow.decoder.estimator.fp32.onnx') {
        return false;
      }
      if (lower == 'speech_tokenizer_v3.batch.onnx') return false;
    }
    return true;
  }

  static Map<String, Object?> _artifactConfiguration(
    OfflineSpeechModelDefinition model,
    Map<String, Object?> configuration,
  ) {
    return switch (model.id) {
      'whisper' => <String, Object?>{
        'model': configuration['model'] ?? 'small',
      },
      'kokoro-82m' => <String, Object?>{
        'quantization': configuration['quantization'] ?? 'int8',
      },
      _ => const <String, Object?>{},
    };
  }

  static String _repositoryFor(
    OfflineSpeechModelDefinition model,
    Map<String, Object?> configuration,
  ) {
    if (model.id == 'kokoro-82m' && configuration['quantization'] == 'int8') {
      return 'csukuangfj/kokoro-int8-multi-lang-v1_1';
    }
    if (model.id == 'whisper') {
      return switch (configuration['model']) {
        'tiny' => 'Systran/faster-whisper-tiny',
        'base' => 'Systran/faster-whisper-base',
        'medium' => 'Systran/faster-whisper-medium',
        'large-v3-turbo' => 'mobiuslabsgmbh/faster-whisper-large-v3-turbo',
        _ => 'Systran/faster-whisper-small',
      };
    }
    return model.repository;
  }

  String? _findExecutable(String name) {
    if (p.isAbsolute(name) && File(name).existsSync()) return name;
    final pathValue = Platform.environment['PATH'];
    if (pathValue == null) return null;
    for (final directory in pathValue.split(Platform.isWindows ? ';' : ':')) {
      final candidate = File(p.join(directory, name));
      if (candidate.existsSync()) return candidate.path;
    }
    return null;
  }

  Future<File> _writeRuntimeHost() async {
    final directory = Directory(modelsRoot);
    await directory.create(recursive: true);
    final file = File(p.join(directory.path, 'runtime_host.py'));
    if (!await file.exists() ||
        await file.readAsString() != _runtimeHostSource) {
      await file.writeAsString(_runtimeHostSource, flush: true);
    }
    return file;
  }

  void _setState(String modelId, OfflineSpeechModelState state) {
    _states[modelId] = state;
    notifyListeners();
  }
}

class _DownloadCancellation {
  bool cancelled = false;
  HttpClient? client;

  void cancel() {
    cancelled = true;
    client?.close(force: true);
  }

  void throwIfCancelled() {
    if (cancelled) throw const OfflineSpeechDownloadCancelled();
  }

  void close() {
    client?.close(force: true);
    client = null;
  }
}

class _RemoteModelFile {
  const _RemoteModelFile({
    required this.path,
    required this.size,
    required this.uri,
  });

  final String path;
  final int size;
  final Uri uri;
}

const String _runtimeHostSource = r'''
import argparse, base64, json, os, sys, time, traceback

def device(config):
    value = config.get("device", "auto")
    return None if value == "auto" else value

def load(runtime, model_dir, config):
    if runtime == "funAsr":
        from funasr import AutoModel
        kwargs = {"model": model_dir, "trust_remote_code": True}
        if device(config): kwargs["device"] = device(config)
        return AutoModel(**kwargs)
    if runtime == "qwenAsr":
        import torch
        from qwen_asr import Qwen3ASRModel
        dtype = config.get("dtype", "auto")
        kwargs = {"device_map": device(config) or "auto"}
        if dtype != "auto": kwargs["dtype"] = getattr(torch, dtype)
        return Qwen3ASRModel.from_pretrained(model_dir, **kwargs)
    if runtime == "qwenTts":
        import torch
        from qwen_tts import Qwen3TTSModel
        dtype = config.get("dtype", "auto")
        kwargs = {"device_map": device(config) or "auto"}
        if dtype != "auto": kwargs["dtype"] = getattr(torch, dtype)
        return Qwen3TTSModel.from_pretrained(model_dir, **kwargs)
    if runtime == "cosyVoice":
        from cosyvoice.cli.cosyvoice import AutoModel
        return AutoModel(model_dir=model_dir)
    if runtime == "fasterWhisper":
        import ctranslate2
        from faster_whisper import WhisperModel
        selected_device = config.get("device", "auto")
        if selected_device == "auto":
            selected_device = "cuda" if ctranslate2.get_cuda_device_count() else "cpu"
        return WhisperModel(
            model_dir,
            device=selected_device,
            compute_type=config.get("compute_type", "default"),
            cpu_threads=int(config.get("threads", 4)),
        )
    if runtime == "sherpaOnnx":
        import sherpa_onnx
        if os.path.isfile(os.path.join(model_dir, "voices.bin")):
            model_name = "model.int8.onnx" if os.path.isfile(os.path.join(model_dir, "model.int8.onnx")) else "model.onnx"
            kokoro = sherpa_onnx.OfflineTtsKokoroModelConfig(
                model=os.path.join(model_dir, model_name),
                voices=os.path.join(model_dir, "voices.bin"),
                tokens=os.path.join(model_dir, "tokens.txt"),
                data_dir=os.path.join(model_dir, "espeak-ng-data"),
                lexicon=",".join([
                    os.path.join(model_dir, "lexicon-us-en.txt"),
                    os.path.join(model_dir, "lexicon-zh.txt"),
                ]),
            )
            tts_config = sherpa_onnx.OfflineTtsConfig(
                model=sherpa_onnx.OfflineTtsModelConfig(
                    kokoro=kokoro,
                    provider=config.get("provider", "cpu"),
                    num_threads=int(config.get("threads", 4)),
                ),
                rule_fsts=",".join([
                    os.path.join(model_dir, "phone-zh.fst"),
                    os.path.join(model_dir, "date-zh.fst"),
                    os.path.join(model_dir, "number-zh.fst"),
                ]),
                max_num_sentences=int(config.get("max_num_sentences", 1)),
            )
            if not tts_config.validate(): raise RuntimeError("Kokoro 配置无效")
            return sherpa_onnx.OfflineTts(tts_config)
        files = os.listdir(model_dir)
        def transducer_file(prefix):
            matches = [f for f in files if f.startswith(prefix + "-") and f.endswith(".onnx")]
            matches.sort(key=lambda f: (".int8.onnx" not in f, f))
            return os.path.join(model_dir, matches[0]) if matches else None
        encoder = transducer_file("encoder")
        decoder = transducer_file("decoder")
        joiner = transducer_file("joiner")
        if not all([encoder, decoder, joiner]): raise RuntimeError("Zipformer 模型文件不完整")
        return sherpa_onnx.OnlineRecognizer.from_transducer(
            tokens=os.path.join(model_dir, "tokens.txt"),
            encoder=encoder,
            decoder=decoder,
            joiner=joiner,
            num_threads=int(config.get("threads", 4)),
            sample_rate=16000,
            feature_dim=80,
            decoding_method=config.get("decoding_method", "greedy_search"),
            max_active_paths=int(config.get("max_active_paths", 4)),
            hotwords_file=config.get("hotwords_file", ""),
            hotwords_score=float(config.get("hotwords_score", 1.5)),
            blank_penalty=float(config.get("blank_penalty", 0.0)),
            modeling_unit="bpe",
            bpe_vocab=os.path.join(model_dir, "bpe.vocab"),
            provider=config.get("provider", "cpu"),
        )
    raise RuntimeError("不支持的运行时: " + runtime)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--runtime", required=True)
    parser.add_argument("--model", required=True)
    parser.add_argument("--config", required=True)
    args = parser.parse_args()
    config = json.loads(base64.urlsafe_b64decode(args.config).decode("utf-8"))
    loaded = load(args.runtime, args.model, config)
    if loaded is None: raise RuntimeError("模型加载失败")
    print("OPENHAND_模型就绪", flush=True)
    while True: time.sleep(1)

try:
    main()
except KeyboardInterrupt:
    pass
except Exception:
    traceback.print_exc()
    sys.exit(1)
''';

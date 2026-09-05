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
  preparing,
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

class OfflineSpeechInferenceTimeout implements Exception {
  const OfflineSpeechInferenceTimeout();

  @override
  String toString() => '模型推理超时，请缩短输入后重试。';
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

class OfflineSpeechTestResult {
  const OfflineSpeechTestResult._({this.audioPath, this.transcript});

  const OfflineSpeechTestResult.synthesis(String audioPath)
    : this._(audioPath: audioPath);

  const OfflineSpeechTestResult.recognition(String transcript)
    : this._(transcript: transcript);

  final String? audioPath;
  final String? transcript;
}

abstract interface class OfflineSpeechRuntimeAdapter {
  Future<Process> start({
    required String pythonExecutable,
    required String runnerPath,
    required OfflineSpeechModelDefinition model,
    required String modelPath,
    required Map<String, Object?> configuration,
    required String workingDirectory,
    required Map<String, String> environment,
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
    required String workingDirectory,
    required Map<String, String> environment,
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
      workingDirectory: workingDirectory,
      environment: environment,
    );
  }
}

class _OfflineSpeechRuntimeSpec {
  const _OfflineSpeechRuntimeSpec({
    required this.revision,
    required this.pythonVersion,
    required this.estimatedStorageGiB,
    required this.packages,
    required this.smokeTest,
    this.buildPackages = const <String>[],
    this.disableBuildIsolation = false,
    this.sourceRepository,
    this.sourceRevision,
  });

  final String revision;
  final String pythonVersion;
  final double estimatedStorageGiB;
  final List<String> packages;
  final String smokeTest;
  final List<String> buildPackages;
  final bool disableBuildIsolation;
  final String? sourceRepository;
  final String? sourceRevision;

  bool get requiresSource => sourceRepository != null;
}

class OfflineSpeechModelService extends ChangeNotifier {
  OfflineSpeechModelService._() {
    unawaited(_inspectHardware());
  }

  static final OfflineSpeechModelService instance =
      OfflineSpeechModelService._();
  static const String testSampleText = '你好，这是一段 OpenHand 本地语音朗读测试。';
  static const Duration _runtimeStartTimeout = Duration(minutes: 5);
  static const Duration _inferenceTimeout = Duration(minutes: 5);
  static const Duration _runtimeInstallTimeout = Duration(minutes: 45);
  static const Duration _downloadNotifyInterval = Duration(milliseconds: 80);
  static const Duration _downloadIdleTimeout = Duration(seconds: 60);
  static const int _runtimeNetworkAttempts = 2;
  static const int _runtimeErrorCharacters = 8 * 1024;
  static const List<String> _proxyEnvironmentKeys = <String>[
    'HTTP_PROXY',
    'HTTPS_PROXY',
    'ALL_PROXY',
    'http_proxy',
    'https_proxy',
    'all_proxy',
    'NO_PROXY',
    'no_proxy',
  ];
  static const Map<OfflineSpeechRuntime, _OfflineSpeechRuntimeSpec>
  _runtimeSpecs = <OfflineSpeechRuntime, _OfflineSpeechRuntimeSpec>{
    OfflineSpeechRuntime.funAsr: _OfflineSpeechRuntimeSpec(
      revision: 'funasr-1.4.14-v1',
      pythonVersion: '3.12',
      estimatedStorageGiB: 3,
      packages: <String>[
        'torch==2.11.0',
        'torchaudio==2.11.0',
        'funasr==1.4.14',
      ],
      smokeTest: 'from funasr import AutoModel',
    ),
    OfflineSpeechRuntime.qwenAsr: _OfflineSpeechRuntimeSpec(
      revision: 'qwen-asr-0.0.6-v1',
      pythonVersion: '3.12',
      estimatedStorageGiB: 3,
      packages: <String>[
        'torch==2.11.0',
        'torchaudio==2.11.0',
        'qwen-asr==0.0.6',
      ],
      smokeTest: 'from qwen_asr import Qwen3ASRModel',
    ),
    OfflineSpeechRuntime.fasterWhisper: _OfflineSpeechRuntimeSpec(
      revision: 'faster-whisper-1.2.1-v1',
      pythonVersion: '3.12',
      estimatedStorageGiB: 1,
      packages: <String>['faster-whisper==1.2.1'],
      smokeTest: 'from faster_whisper import WhisperModel',
    ),
    OfflineSpeechRuntime.sherpaOnnx: _OfflineSpeechRuntimeSpec(
      revision: 'sherpa-onnx-1.13.7-v1',
      pythonVersion: '3.12',
      estimatedStorageGiB: 0.5,
      packages: <String>['sherpa-onnx==1.13.7'],
      smokeTest: 'import sherpa_onnx',
    ),
    OfflineSpeechRuntime.cosyVoice: _OfflineSpeechRuntimeSpec(
      revision: 'cosyvoice-074ca6d-v4',
      pythonVersion: '3.10',
      estimatedStorageGiB: 4,
      buildPackages: <String>[
        'setuptools<81',
        'wheel',
        'Cython==0.29.35',
        'numpy==1.26.4',
      ],
      disableBuildIsolation: true,
      packages: <String>[
        'torch==2.3.1',
        'torchaudio==2.3.1',
        'conformer==0.3.2',
        'diffusers==0.29.0',
        'einops',
        'gdown==5.1.0',
        'hydra-core==1.3.2',
        'HyperPyYAML==1.2.3',
        'inflect==7.3.1',
        'librosa==0.10.2',
        'lightning==2.2.4',
        'matplotlib==3.7.5',
        'modelscope==1.20.0',
        'networkx==3.1',
        'numpy==1.26.4',
        'omegaconf==2.3.0',
        'onnx==1.16.0',
        'onnxruntime==1.18.0',
        'openai-whisper==20231117',
        'protobuf>=4.25,<5',
        'pyarrow==18.1.0',
        'pydantic==2.7.0',
        'pyworld==0.3.4',
        'PyYAML>=6.0',
        'rich==13.7.1',
        'soundfile==0.12.1',
        'tiktoken',
        'tqdm',
        'transformers==4.51.3',
        'wetext==0.0.4',
        'wget==3.2',
        'x-transformers==2.11.24',
      ],
      smokeTest: 'from cosyvoice.cli.cosyvoice import AutoModel',
      sourceRepository: 'https://github.com/QwenAudio/CosyVoice.git',
      sourceRevision: '074ca6dc9e80a2f424f1f74b48bdd7d3fea531cc',
    ),
    OfflineSpeechRuntime.qwenTts: _OfflineSpeechRuntimeSpec(
      revision: 'qwen-tts-0.1.1-v1',
      pythonVersion: '3.12',
      estimatedStorageGiB: 3,
      packages: <String>[
        'torch==2.11.0',
        'torchaudio==2.11.0',
        'qwen-tts==0.1.1',
      ],
      smokeTest: 'from qwen_tts import Qwen3TTSModel',
    ),
  };
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
  final Map<String, _OfflineSpeechRuntimeSession> _processes =
      <String, _OfflineSpeechRuntimeSession>{};
  final Map<OfflineSpeechRuntime, Future<void>> _runtimePreparations =
      <OfflineSpeechRuntime, Future<void>>{};
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
    final runtimeUnavailableReason = _runtimePreparationUnavailableReason(
      model.runtime,
    );
    if (runtimeUnavailableReason != null) {
      return OfflineSpeechModelAvailability(
        available: false,
        reason: runtimeUnavailableReason,
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
    final runtimeStorageGiB = requiresRuntimePreparation(model)
        ? _runtimeSpecs[model.runtime]!.estimatedStorageGiB
        : 0;
    final requiredStorageGiB = requirement.storageGiB + runtimeStorageGiB;
    final freeStorageGiB = profile.freeStorageBytes / (1024 * 1024 * 1024);
    if (freeStorageGiB < requiredStorageGiB) {
      return OfflineSpeechModelAvailability(
        available: false,
        reason:
            '模型及运行环境至少需要 ${requiredStorageGiB.toStringAsFixed(1)} GB 可用空间，当前约 ${freeStorageGiB.toStringAsFixed(1)} GB。',
      );
    }
    return OfflineSpeechModelAvailability(
      available: true,
      reason:
          '设备满足 ${requirement.memoryGiB} GB 内存、${requirement.logicalCores} 核和 ${requiredStorageGiB.toStringAsFixed(1)} GB 空间要求。',
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
    return requiresModelFilesForConfiguration(model, configuration) ||
        requiresRuntimePreparation(model);
  }

  bool requiresModelFilesForConfiguration(
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

  bool requiresRuntimePreparation(OfflineSpeechModelDefinition model) {
    return !_isRuntimeReady(model.runtime);
  }

  String runtimePreparationSizeLabel(OfflineSpeechModelDefinition model) {
    final size = _runtimeSpecs[model.runtime]!.estimatedStorageGiB;
    return '约 ${size == size.roundToDouble() ? size.toInt() : size} GB';
  }

  Future<void> download(
    OfflineSpeechModelDefinition model,
    Map<String, Object?> configuration,
  ) async {
    if (_downloadCancellations.containsKey(model.id)) return;
    await SystemProxyResolver.instance.initialize();
    await _inspectHardware();
    final availability = availabilityFor(model, configuration);
    if (!availability.available) throw StateError(availability.reason);
    final target = Directory(modelDirectory(model));
    final staging = Directory('${target.path}.partial');
    final downloadModelFiles = requiresModelFilesForConfiguration(
      model,
      configuration,
    );
    final cancellation = _DownloadCancellation();
    _downloadCancellations[model.id] = cancellation;
    _setState(
      model.id,
      OfflineSpeechModelState(
        lifecycle: downloadModelFiles
            ? OfflineSpeechLifecycle.downloading
            : OfflineSpeechLifecycle.preparing,
        message: downloadModelFiles ? '正在读取模型文件清单…' : '正在检查隔离运行环境…',
      ),
    );
    var receivedBytes = 0;
    var totalBytes = 0;
    var completedFiles = 0;
    var totalFiles = 0;
    try {
      if (await staging.exists()) await staging.delete(recursive: true);
      if (downloadModelFiles) {
        await staging.create(recursive: true);
        final files = await _loadRepositoryFiles(
          model,
          configuration,
          cancellation,
        );
        if (files.isEmpty) throw StateError('模型仓库没有可下载的运行文件。');
        totalBytes = files.fold<int>(0, (sum, file) => sum + file.size);
        totalFiles = files.length;
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
              await for (final chunk in opened.response.timeout(
                _downloadIdleTimeout,
              )) {
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
                      totalFiles: totalFiles,
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
      }
      cancellation.throwIfCancelled();
      _setState(
        model.id,
        const OfflineSpeechModelState(
          lifecycle: OfflineSpeechLifecycle.preparing,
          message: '正在准备隔离运行环境…',
        ),
      );
      await _ensureRuntime(model, cancellation);
      cancellation.throwIfCancelled();
      _setState(
        model.id,
        OfflineSpeechModelState(
          lifecycle: OfflineSpeechLifecycle.installed,
          receivedBytes: receivedBytes,
          totalBytes: math.max(totalBytes, receivedBytes),
          completedFiles: completedFiles,
          totalFiles: totalFiles,
          message: '模型及运行环境已准备完成',
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
          lifecycle:
              retained &&
                  !requiresDownloadForConfiguration(model, configuration)
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
      throw StateError('模型文件或隔离运行环境尚未就绪，请点击更新按钮完成准备。');
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
      final runtimeRoot = _runtimeDirectory(model.runtime);
      final python = _runtimePythonExecutable(runtimeRoot);
      if (!File(python).existsSync()) {
        throw StateError('隔离运行环境已损坏，请点击更新按钮自动修复。');
      }
      final runner = await _writeRuntimeHost();
      process = await _runtimeAdapters[model.runtime]!.start(
        pythonExecutable: python,
        runnerPath: runner.path,
        model: model,
        modelPath: modelDirectory(model),
        configuration: configuration,
        workingDirectory: runtimeRoot,
        environment: _runtimeEnvironment(model.runtime, runtimeRoot),
      );
      final startedSession = _OfflineSpeechRuntimeSession(process);
      _processes[model.id] = startedSession;
      unawaited(
        process.exitCode.then((code) {
          if (!startedSession.ready.isCompleted) {
            startedSession.ready.completeError(
              StateError(
                startedSession.errors.trim().isEmpty
                    ? '模型运行时异常退出（$code）。'
                    : _runtimeStartFailureMessage(
                        model,
                        startedSession.errors,
                        code,
                      ),
              ),
            );
          }
          startedSession.failPending(StateError('模型运行时已退出（$code）。'));
          if (identical(_processes[model.id], startedSession)) {
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
      await startedSession.ready.future.timeout(_runtimeStartTimeout);
      _setState(
        model.id,
        const OfflineSpeechModelState(
          lifecycle: OfflineSpeechLifecycle.running,
        ),
      );
    } catch (error) {
      _processes.remove(model.id);
      process?.kill(ProcessSignal.sigkill);
      if (_isRuntimeDependencyFailure(error)) {
        await _invalidateRuntime(model.runtime);
      }
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
    final session = _processes.remove(model.id);
    if (session == null) {
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
    session.failPending(StateError('模型已停止。'));
    final process = session.process;
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

  Future<OfflineSpeechTestResult> test(
    OfflineSpeechModelDefinition model,
    Map<String, Object?> configuration, {
    String? audioPath,
    String sampleText = testSampleText,
  }) async {
    final wasRunning = _processes.containsKey(model.id);
    if (!wasRunning) await start(model, configuration);
    Directory? outputDirectory;
    try {
      final session = _processes[model.id];
      if (session == null) throw StateError('模型运行时尚未就绪。');
      if (model.kind == OfflineSpeechKind.recognition) {
        final source = audioPath?.trim() ?? '';
        if (source.isEmpty || !await File(source).exists()) {
          throw StateError('没有可识别的录音文件。');
        }
        final response = await session.request(<String, Object?>{
          'operation': 'recognize',
          'audio_path': source,
        }, timeout: _inferenceTimeout);
        return OfflineSpeechTestResult.recognition(
          '${response['transcript'] ?? ''}'.trim(),
        );
      }
      outputDirectory = await Directory.systemTemp.createTemp(
        'openhand_speech_test_',
      );
      final outputPath = p.join(outputDirectory.path, 'sample.wav');
      final response = await session.request(<String, Object?>{
        'operation': 'synthesize',
        'text': sampleText,
        'output_path': outputPath,
      }, timeout: _inferenceTimeout);
      final generatedPath = '${response['audio_path'] ?? ''}'.trim();
      final generated = File(generatedPath);
      if (generatedPath.isEmpty ||
          !await generated.exists() ||
          await generated.length() == 0) {
        throw StateError('模型没有生成有效音频。');
      }
      return OfflineSpeechTestResult.synthesis(generatedPath);
    } catch (error) {
      if (outputDirectory != null && await outputDirectory.exists()) {
        await outputDirectory.delete(recursive: true);
      }
      if (wasRunning && error is OfflineSpeechInferenceTimeout) {
        await stop(model);
      }
      rethrow;
    } finally {
      if (!wasRunning) await stop(model);
    }
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
      final payload = jsonDecode(
        await utf8.decodeStream(response.timeout(_downloadIdleTimeout)),
      );
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

  Future<void> _ensureRuntime(
    OfflineSpeechModelDefinition model,
    _DownloadCancellation cancellation,
  ) async {
    if (_isRuntimeReady(model.runtime)) return;
    final pending = _runtimePreparations[model.runtime];
    if (pending != null) {
      _setState(
        model.id,
        const OfflineSpeechModelState(
          lifecycle: OfflineSpeechLifecycle.preparing,
          message: '正在等待同类模型的隔离运行环境…',
        ),
      );
      await Future.any<void>(<Future<void>>[
        pending,
        cancellation.cancelSignal.then<void>(
          (_) => throw const OfflineSpeechDownloadCancelled(),
        ),
      ]);
      cancellation.throwIfCancelled();
      return;
    }

    final preparation = _prepareRuntime(model, cancellation);
    _runtimePreparations[model.runtime] = preparation;
    try {
      await preparation;
    } finally {
      if (identical(_runtimePreparations[model.runtime], preparation)) {
        unawaited(_runtimePreparations.remove(model.runtime));
      }
    }
  }

  Future<void> _prepareRuntime(
    OfflineSpeechModelDefinition model,
    _DownloadCancellation cancellation,
  ) async {
    final spec = _runtimeSpecs[model.runtime]!;
    final target = Directory(_runtimeDirectory(model.runtime));
    final staging = Directory('${target.path}.partial');
    final stagingMarker = File(
      p.join(staging.path, 'openhand-runtime.partial.json'),
    );
    final environment = _runtimeEnvironment(model.runtime, staging.path);
    final uv = _findUvExecutable();
    final compatiblePython = _findExecutable(
      Platform.isWindows
          ? 'python${spec.pythonVersion}.exe'
          : 'python${spec.pythonVersion}',
    );
    if (uv == null && compatiblePython == null) {
      throw StateError(
        '准备运行环境需要 uv 或 Python ${spec.pythonVersion}。请安装后重新检测设备。',
      );
    }
    final git = spec.requiresSource
        ? _findExecutable(Platform.isWindows ? 'git.exe' : 'git')
        : null;
    if (spec.requiresSource && git == null) {
      throw StateError('准备 ${model.name} 运行环境需要 Git。请安装后重新检测设备。');
    }

    try {
      var canResume = false;
      if (await stagingMarker.exists()) {
        try {
          final payload = jsonDecode(await stagingMarker.readAsString());
          canResume =
              payload is Map &&
              payload['runtime'] == model.runtime.name &&
              payload['revision'] == spec.revision;
        } catch (_) {
          canResume = false;
        }
      }
      if (!canResume && await staging.exists()) {
        await staging.delete(recursive: true);
      }
      await staging.create(recursive: true);
      if (!canResume) {
        await stagingMarker.writeAsString(
          jsonEncode(<String, Object?>{
            'runtime': model.runtime.name,
            'revision': spec.revision,
          }),
          flush: true,
        );
      }
      final venvPath = p.join(staging.path, '.venv');
      if (!File(_runtimePythonExecutable(staging.path)).existsSync()) {
        if (await Directory(venvPath).exists()) {
          await Directory(venvPath).delete(recursive: true);
        }
        await _runRuntimeCommand(
          model: model,
          cancellation: cancellation,
          executable: uv ?? compatiblePython!,
          arguments: uv != null
              ? <String>['venv', '--python', spec.pythonVersion, venvPath]
              : <String>['-m', 'venv', venvPath],
          environment: environment,
          message: '正在创建 Python ${spec.pythonVersion} 隔离环境…',
        );
      }

      if (spec.requiresSource) {
        final sourcePath = p.join(staging.path, 'source');
        final sourceMarker = File(p.join(sourcePath, 'openhand-source-ready'));
        if (!await sourceMarker.exists()) {
          if (await Directory(sourcePath).exists()) {
            await Directory(sourcePath).delete(recursive: true);
          }
          await _runRuntimeCommand(
            model: model,
            cancellation: cancellation,
            executable: git!,
            arguments: <String>['init', sourcePath],
            environment: environment,
            message: '正在初始化官方运行时源码…',
          );
          await _runRuntimeCommand(
            model: model,
            cancellation: cancellation,
            executable: git,
            arguments: <String>[
              '-C',
              sourcePath,
              'remote',
              'add',
              'origin',
              spec.sourceRepository!,
            ],
            environment: environment,
            message: '正在连接官方运行时仓库…',
          );
          await _runRuntimeCommand(
            model: model,
            cancellation: cancellation,
            executable: git,
            arguments: <String>[
              '-C',
              sourcePath,
              'fetch',
              '--depth',
              '1',
              'origin',
              spec.sourceRevision!,
            ],
            environment: environment,
            message: '正在下载官方运行时源码…',
          );
          await _runRuntimeCommand(
            model: model,
            cancellation: cancellation,
            executable: git,
            arguments: <String>[
              '-C',
              sourcePath,
              'checkout',
              '--detach',
              'FETCH_HEAD',
            ],
            environment: environment,
            message: '正在校验官方运行时版本…',
          );
          await _runRuntimeCommand(
            model: model,
            cancellation: cancellation,
            executable: git,
            arguments: <String>[
              '-C',
              sourcePath,
              'submodule',
              'update',
              '--init',
              '--recursive',
              '--depth',
              '1',
            ],
            environment: environment,
            message: '正在下载官方运行时组件…',
          );
          await sourceMarker.writeAsString(spec.sourceRevision!, flush: true);
        }
      }

      final runtimePython = _runtimePythonExecutable(staging.path);
      if (spec.buildPackages.isNotEmpty) {
        await _runRuntimeCommand(
          model: model,
          cancellation: cancellation,
          executable: uv ?? runtimePython,
          arguments: uv != null
              ? <String>[
                  'pip',
                  'install',
                  '--python',
                  runtimePython,
                  ...spec.buildPackages,
                ]
              : <String>[
                  '-m',
                  'pip',
                  'install',
                  '--disable-pip-version-check',
                  ...spec.buildPackages,
                ],
          environment: environment,
          message: '正在安装运行环境构建组件…',
        );
      }
      await _runRuntimeCommand(
        model: model,
        cancellation: cancellation,
        executable: uv ?? runtimePython,
        arguments: uv != null
            ? <String>[
                'pip',
                'install',
                if (spec.disableBuildIsolation) '--no-build-isolation',
                '--python',
                runtimePython,
                ...spec.packages,
              ]
            : <String>[
                '-m',
                'pip',
                'install',
                '--disable-pip-version-check',
                if (spec.disableBuildIsolation) '--no-build-isolation',
                ...spec.packages,
              ],
        environment: environment,
        message: '正在安装 ${model.name} 运行依赖…',
      );
      await _runRuntimeCommand(
        model: model,
        cancellation: cancellation,
        executable: runtimePython,
        arguments: <String>['-c', spec.smokeTest],
        workingDirectory: staging.path,
        environment: environment,
        message: '正在验证 ${model.name} 运行环境…',
        timeout: const Duration(minutes: 5),
      );
      if (model.runtime == OfflineSpeechRuntime.cosyVoice) {
        await _runRuntimeCommand(
          model: model,
          cancellation: cancellation,
          executable: runtimePython,
          arguments: <String>[
            '-c',
            '${spec.smokeTest}; AutoModel(model_dir=${jsonEncode(modelDirectory(model))})',
          ],
          workingDirectory: staging.path,
          environment: environment,
          message: '正在验证 ${model.name} 模型加载…',
          timeout: _runtimeStartTimeout,
        );
      }
      cancellation.throwIfCancelled();
      await File(p.join(staging.path, 'openhand-runtime.json')).writeAsString(
        const JsonEncoder.withIndent('  ').convert(<String, Object?>{
          'runtime': model.runtime.name,
          'revision': spec.revision,
          'python': spec.pythonVersion,
          'prepared_at': DateTime.now().toUtc().toIso8601String(),
        }),
        flush: true,
      );
      await stagingMarker.delete();
      if (await target.exists()) await target.delete(recursive: true);
      await staging.rename(target.path);
    } catch (_) {
      if (cancellation.cancelled && await staging.exists()) {
        await staging.delete(recursive: true);
      }
      rethrow;
    }
  }

  Future<void> _runRuntimeCommand({
    required OfflineSpeechModelDefinition model,
    required _DownloadCancellation cancellation,
    required String executable,
    required List<String> arguments,
    required Map<String, String> environment,
    required String message,
    String? workingDirectory,
    Duration timeout = _runtimeInstallTimeout,
  }) async {
    cancellation.throwIfCancelled();
    var effectiveEnvironment = environment;
    for (var attempt = 0; attempt < _runtimeNetworkAttempts; attempt++) {
      _setState(
        model.id,
        OfflineSpeechModelState(
          lifecycle: OfflineSpeechLifecycle.preparing,
          message: attempt == 0 ? message : '网络连接不稳定，正在按当前系统代理重试…',
        ),
      );
      final result = await runTrackedProcessWithLineLogging(
        executable,
        arguments,
        timeout: timeout,
        processStartTimeout: const Duration(seconds: 20),
        tag: 'offline_speech.runtime.${model.runtime.name}',
        workingDirectory: workingDirectory,
        environment: effectiveEnvironment,
        cancelSignal: cancellation.cancelSignal,
        maxCapturedLinesPerStream: 80,
        maxCapturedCharactersPerStream: 32 * 1024,
      );
      if (result.cancelled || cancellation.cancelled) {
        throw const OfflineSpeechDownloadCancelled();
      }
      if (result.timedOut) {
        throw StateError('$message超时，请检查网络后重试。');
      }
      if (result.exitCode == 0) return;
      final details = _processFailureTail(
        <String>[
          result.stderr,
          result.stdout,
        ].where((value) => value.trim().isNotEmpty).join('\n'),
      );
      final networkFailure = _isTransientNetworkFailure(details);
      if (attempt + 1 < _runtimeNetworkAttempts && networkFailure) {
        await SystemProxyResolver.instance.initialize();
        effectiveEnvironment = Map<String, String>.of(environment);
        for (final key in _proxyEnvironmentKeys) {
          effectiveEnvironment[key] = '';
        }
        effectiveEnvironment.addAll(
          SystemProxyResolver.instance.resolveSubprocessEnvironment(),
        );
        continue;
      }
      throw StateError(
        details.isEmpty
            ? '$message失败（退出码 ${result.exitCode}）。'
            : '$message失败。\n$details'
                  '${networkFailure ? '\n请检查“设置 > 系统”的代理配置与代理服务状态。' : ''}',
      );
    }
  }

  String? _runtimePreparationUnavailableReason(OfflineSpeechRuntime runtime) {
    if (_isRuntimeReady(runtime)) return null;
    final spec = _runtimeSpecs[runtime]!;
    final hasUv = _findUvExecutable() != null;
    final compatiblePython = _findExecutable(
      Platform.isWindows
          ? 'python${spec.pythonVersion}.exe'
          : 'python${spec.pythonVersion}',
    );
    if (!hasUv && compatiblePython == null) {
      return '首次运行需要 uv 或 Python ${spec.pythonVersion}，当前设备尚未检测到。';
    }
    if (spec.requiresSource &&
        _findExecutable(Platform.isWindows ? 'git.exe' : 'git') == null) {
      return '首次运行 ${runtime.name} 需要 Git，当前设备尚未检测到。';
    }
    return null;
  }

  bool _isRuntimeReady(OfflineSpeechRuntime runtime) {
    final spec = _runtimeSpecs[runtime]!;
    final root = _runtimeDirectory(runtime);
    final marker = File(p.join(root, 'openhand-runtime.json'));
    if (!marker.existsSync() ||
        !File(_runtimePythonExecutable(root)).existsSync()) {
      return false;
    }
    if (spec.requiresSource &&
        (!File(
              p.join(root, 'source', 'cosyvoice', 'cli', 'cosyvoice.py'),
            ).existsSync() ||
            !Directory(
              p.join(root, 'source', 'third_party', 'Matcha-TTS'),
            ).existsSync())) {
      return false;
    }
    try {
      final payload = jsonDecode(marker.readAsStringSync());
      return payload is Map &&
          payload['runtime'] == runtime.name &&
          payload['revision'] == spec.revision;
    } catch (_) {
      return false;
    }
  }

  String _runtimeDirectory(OfflineSpeechRuntime runtime) {
    return p.join(modelsRoot, '.runtimes', runtime.name);
  }

  String _runtimePythonExecutable(String runtimeRoot) {
    return Platform.isWindows
        ? p.join(runtimeRoot, '.venv', 'Scripts', 'python.exe')
        : p.join(runtimeRoot, '.venv', 'bin', 'python');
  }

  Map<String, String> _runtimeEnvironment(
    OfflineSpeechRuntime runtime,
    String runtimeRoot,
  ) {
    final environment = <String, String>{
      'PYTHONUNBUFFERED': '1',
      'PYTHONNOUSERSITE': '1',
      'PYTHONPATH': '',
      'PIP_DISABLE_PIP_VERSION_CHECK': '1',
      'UV_NATIVE_TLS': 'true',
      'UV_CACHE_DIR': p.join(
        OpenHandPaths.defaultCacheDirectoryPath(),
        'offline_speech',
        'uv',
      ),
      'UV_PYTHON_INSTALL_DIR': p.join(modelsRoot, '.python'),
      'UV_LINK_MODE': 'copy',
      'HF_HOME': p.join(runtimeRoot, 'cache', 'huggingface'),
      'MODELSCOPE_CACHE': p.join(runtimeRoot, 'cache', 'modelscope'),
      for (final key in _proxyEnvironmentKeys) key: '',
      ...SystemProxyResolver.instance.resolveSubprocessEnvironment(),
    };
    if (_runtimeSpecs[runtime]!.requiresSource) {
      final source = p.join(runtimeRoot, 'source');
      final paths = <String>[
        source,
        p.join(source, 'third_party', 'Matcha-TTS'),
      ];
      environment['PYTHONPATH'] = paths.join(Platform.isWindows ? ';' : ':');
    }
    return environment;
  }

  String? _findUvExecutable() {
    final discovered = _findExecutable(Platform.isWindows ? 'uv.exe' : 'uv');
    if (discovered != null) return discovered;
    final home = OpenHandPaths.homeDirectoryPath();
    final candidates = Platform.isWindows
        ? <String>[
            p.join(home, '.local', 'bin', 'uv.exe'),
            p.join(
              Platform.environment['LOCALAPPDATA'] ?? home,
              'Programs',
              'uv',
              'uv.exe',
            ),
          ]
        : <String>[
            '/opt/homebrew/bin/uv',
            '/usr/local/bin/uv',
            p.join(home, '.local', 'bin', 'uv'),
            p.join(home, '.cargo', 'bin', 'uv'),
          ];
    return candidates.where((path) => File(path).existsSync()).firstOrNull;
  }

  Future<void> _invalidateRuntime(OfflineSpeechRuntime runtime) async {
    final marker = File(
      p.join(_runtimeDirectory(runtime), 'openhand-runtime.json'),
    );
    if (await marker.exists()) await marker.delete();
  }

  static bool _isRuntimeDependencyFailure(Object error) {
    final message = '$error'.toLowerCase();
    return message.contains('modulenotfounderror') ||
        message.contains('no module named') ||
        message.contains('importerror') ||
        message.contains('library not loaded') ||
        message.contains('dll load failed');
  }

  static bool _isTransientNetworkFailure(String details) {
    final message = details.toLowerCase();
    return message.contains('request failed') ||
        message.contains('failed to fetch') ||
        message.contains('tls handshake') ||
        message.contains('connection reset') ||
        message.contains('connection refused') ||
        message.contains('network is unreachable') ||
        message.contains('could not resolve host') ||
        message.contains('temporary failure') ||
        message.contains('unexpected eof') ||
        message.contains('early eof') ||
        message.contains('rpc failed');
  }

  static String _runtimeStartFailureMessage(
    OfflineSpeechModelDefinition model,
    String raw,
    int exitCode,
  ) {
    final missing = RegExp(
      r'''No module named ['"]([^'"]+)['"]''',
      caseSensitive: false,
    ).firstMatch(raw);
    if (missing != null) {
      return '隔离运行环境缺少 ${missing.group(1)}，请点击更新按钮自动修复。';
    }
    final details = _processFailureTail(raw);
    return details.isEmpty
        ? '${model.name} 加载失败（退出码 $exitCode）。'
        : '${model.name} 加载失败（退出码 $exitCode）。\n$details';
  }

  static String _processFailureTail(String raw) {
    final lines = raw
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    return lines.skip(math.max(0, lines.length - 10)).join('\n');
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
  final Completer<void> _cancelCompleter = Completer<void>();

  Future<void> get cancelSignal => _cancelCompleter.future;

  void cancel() {
    cancelled = true;
    if (!_cancelCompleter.isCompleted) _cancelCompleter.complete();
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

class _OfflineSpeechRuntimeSession {
  _OfflineSpeechRuntimeSession(this.process) {
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleOutput, onError: _handleStreamError);
    process.stderr.transform(utf8.decoder).listen((chunk) {
      errors += chunk;
      if (errors.length > OfflineSpeechModelService._runtimeErrorCharacters) {
        errors = errors.substring(
          errors.length - OfflineSpeechModelService._runtimeErrorCharacters,
        );
      }
    });
  }

  static const String _responsePrefix = 'OPENHAND_响应 ';

  final Process process;
  final Completer<void> ready = Completer<void>();
  final Map<String, Completer<Map<String, Object?>>> _pending =
      <String, Completer<Map<String, Object?>>>{};
  int _requestSequence = 0;
  String errors = '';

  Future<Map<String, Object?>> request(
    Map<String, Object?> request, {
    required Duration timeout,
  }) async {
    final id = '${++_requestSequence}';
    final completer = Completer<Map<String, Object?>>();
    _pending[id] = completer;
    try {
      final encoded = base64Url.encode(
        utf8.encode(jsonEncode(<String, Object?>{'id': id, ...request})),
      );
      process.stdin.writeln(encoded);
      await process.stdin.flush();
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      throw const OfflineSpeechInferenceTimeout();
    } finally {
      _pending.remove(id);
    }
  }

  void failPending(Object error) {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    _pending.clear();
  }

  void _handleOutput(String line) {
    if (line == 'OPENHAND_模型就绪') {
      if (!ready.isCompleted) ready.complete();
      return;
    }
    if (!line.startsWith(_responsePrefix)) return;
    try {
      final decoded = utf8.decode(
        base64Url.decode(line.substring(_responsePrefix.length)),
      );
      final payload = jsonDecode(decoded);
      if (payload is! Map) return;
      final id = '${payload['id'] ?? ''}';
      final completer = _pending[id];
      if (completer == null || completer.isCompleted) return;
      if (payload['ok'] == true) {
        final result = payload['result'];
        completer.complete(
          result is Map
              ? Map<String, Object?>.from(result)
              : const <String, Object?>{},
        );
      } else {
        completer.completeError(StateError('${payload['error'] ?? '模型推理失败。'}'));
      }
    } catch (error) {
      failPending(StateError('无法解析模型运行时响应：$error'));
    }
  }

  void _handleStreamError(Object error, StackTrace stack) {
    if (!ready.isCompleted) ready.completeError(error, stack);
    failPending(error);
  }
}

const String _runtimeHostSource = r'''
import argparse, array, base64, json, os, sys, traceback, wave

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

def flatten_samples(samples):
    if hasattr(samples, "detach"):
        samples = samples.detach().float().cpu()
    if hasattr(samples, "reshape"):
        samples = samples.reshape(-1)
    if hasattr(samples, "tolist"):
        samples = samples.tolist()
    result = []
    def append(value):
        if isinstance(value, (list, tuple)):
            for item in value: append(item)
        else:
            result.append(float(value))
    append(samples)
    return result

def write_wav(path, samples, sample_rate, volume=1.0):
    values = flatten_samples(samples)
    if not values: raise RuntimeError("模型没有生成音频采样")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    pcm = array.array("h", (
        int(max(-1.0, min(1.0, value * volume)) * 32767) for value in values
    ))
    with wave.open(path, "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(int(sample_rate))
        output.writeframes(pcm.tobytes())

def read_wav(path):
    with wave.open(path, "rb") as source:
        channels = source.getnchannels()
        width = source.getsampwidth()
        sample_rate = source.getframerate()
        frames = source.readframes(source.getnframes())
    if width != 2: raise RuntimeError("录音必须为 16 位 WAV 格式")
    pcm = array.array("h")
    pcm.frombytes(frames)
    if sys.byteorder == "big": pcm.byteswap()
    if channels > 1:
        values = [
            sum(pcm[index:index + channels]) / channels / 32768.0
            for index in range(0, len(pcm), channels)
        ]
    else:
        values = [value / 32768.0 for value in pcm]
    return values, sample_rate

def language(config, canonical=False):
    value = config.get("language", "auto")
    if value == "auto": return None
    if not canonical: return value
    return {
        "zh": "Chinese", "yue": "Cantonese", "en": "English",
        "ja": "Japanese", "ko": "Korean",
    }.get(value, value)

def recognize(runtime, loaded, audio_path, config):
    if runtime == "funAsr":
        if "chunk_size" in config:
            import numpy as np
            samples, _ = read_wav(audio_path)
            chunk_size = [int(value.strip()) for value in str(config["chunk_size"]).split(",")]
            if len(chunk_size) != 3 or chunk_size[1] <= 0:
                raise RuntimeError("流式分块配置必须包含三个有效整数")
            stride = chunk_size[1] * 960
            cache, texts = {}, []
            waveform = np.asarray(samples, dtype=np.float32)
            total = max(1, (len(waveform) + stride - 1) // stride)
            for index in range(total):
                result = loaded.generate(
                    input=waveform[index * stride:(index + 1) * stride],
                    cache=cache,
                    is_final=index == total - 1,
                    chunk_size=chunk_size,
                    encoder_chunk_look_back=int(config.get("encoder_lookback", 4)),
                    decoder_chunk_look_back=int(config.get("decoder_lookback", 1)),
                )
                if result:
                    item = result[0]
                    texts.append(item.get("text", "") if isinstance(item, dict) else str(item))
            return "".join(texts).strip()
        kwargs = {
            "input": audio_path,
            "batch_size_s": int(config.get("batch_size_s", 60)),
            "use_itn": bool(config.get("itn", True)),
        }
        selected_language = language(config)
        if selected_language:
            if "batch_size" not in config:
                selected_language = {
                    "zh": "中文", "yue": "粤语", "en": "英文",
                    "ja": "日文", "ko": "韩文",
                }.get(selected_language, selected_language)
            kwargs["language"] = selected_language
        hotwords = str(config.get("hotwords", "")).strip()
        if hotwords: kwargs["hotword"] = hotwords
        result = loaded.generate(**kwargs)
        if not result: return ""
        text = result[0].get("text", "") if isinstance(result[0], dict) else str(result[0])
        try:
            from funasr.utils.postprocess_utils import rich_transcription_postprocess
            text = rich_transcription_postprocess(text)
        except Exception:
            pass
        return text.strip()
    if runtime == "qwenAsr":
        result = loaded.transcribe(
            audio=audio_path,
            context=str(config.get("hotwords", "")).strip(),
            language=language(config, canonical=True),
            return_time_stamps=False,
        )
        return result[0].text.strip() if result else ""
    if runtime == "fasterWhisper":
        segments, _ = loaded.transcribe(
            audio_path,
            language=language(config),
            task="translate" if config.get("translate", False) else "transcribe",
            beam_size=int(config.get("beam_size", 5)),
            best_of=int(config.get("best_of", 5)),
            temperature=float(config.get("temperature", 0.0)),
            word_timestamps=bool(config.get("word_timestamps", True)),
            vad_filter=bool(config.get("vad", True)),
        )
        return "".join(segment.text for segment in segments).strip()
    if runtime == "sherpaOnnx":
        samples, sample_rate = read_wav(audio_path)
        stream = loaded.create_stream()
        stream.accept_waveform(sample_rate, samples)
        stream.accept_waveform(sample_rate, [0.0] * int(0.66 * sample_rate))
        stream.input_finished()
        while loaded.is_ready(stream): loaded.decode_stream(stream)
        result = loaded.get_result(stream)
        return (result.text if hasattr(result, "text") else str(result)).strip()
    raise RuntimeError("当前运行时不支持语音识别")

def generation_options(config):
    options = {}
    temperature = float(config.get("temperature", 0.7))
    if temperature > 0:
        options["do_sample"] = True
        options["temperature"] = temperature
        options["top_p"] = float(config.get("top_p", 0.8))
    else:
        options["do_sample"] = False
    return options

def synthesize(runtime, loaded, text, output_path, config):
    volume = float(config.get("volume", 1.0))
    if runtime == "qwenTts":
        selected_language = language(config, canonical=True) or "Auto"
        options = generation_options(config)
        if "speaker" in config:
            wavs, sample_rate = loaded.generate_custom_voice(
                text=text,
                language=selected_language,
                speaker=config.get("speaker", "Vivian"),
                instruct=str(config.get("instruct", "")).strip(),
                non_streaming_mode=True,
                **options,
            )
        elif "voice_description" in config:
            wavs, sample_rate = loaded.generate_voice_design(
                text=text,
                language=selected_language,
                instruct=str(config.get("voice_description", "")).strip(),
                non_streaming_mode=True,
                **options,
            )
        else:
            reference_audio = str(config.get("reference_audio", "")).strip()
            if not reference_audio or not os.path.isfile(reference_audio):
                raise RuntimeError("请先选择有效的参考音频，再测试音色克隆模型")
            reference_text = str(config.get("reference_text", "")).strip()
            wavs, sample_rate = loaded.generate_voice_clone(
                text=text,
                language=selected_language,
                ref_audio=reference_audio,
                ref_text=reference_text or None,
                x_vector_only_mode=not bool(reference_text),
                non_streaming_mode=True,
                **options,
            )
        write_wav(output_path, wavs[0], sample_rate, volume)
    elif runtime == "cosyVoice":
        reference_audio = str(config.get("reference_audio", "")).strip()
        if not reference_audio:
            reference_audio = os.path.join(os.getcwd(), "source", "asset", "zero_shot_prompt.wav")
        if not os.path.isfile(reference_audio):
            raise RuntimeError("请先选择有效的参考音频")
        speed = float(config.get("speed", 1.0))
        text_frontend = bool(config.get("text_frontend", True))
        instruct = str(config.get("instruct", "")).strip()
        if hasattr(loaded, "inference_instruct2") and instruct:
            prompt = "You are a helpful assistant. " + instruct + "<|endofprompt|>"
            generated = loaded.inference_instruct2(
                text, prompt, reference_audio, stream=False,
                speed=speed, text_frontend=text_frontend,
            )
        else:
            prompt_text = str(config.get("prompt_text", "")).strip()
            if not prompt_text:
                prompt_text = "You are a helpful assistant.<|endofprompt|>希望你以后能够做的比我还好呦。"
            generated = loaded.inference_zero_shot(
                text, prompt_text, reference_audio, stream=False,
                speed=speed, text_frontend=text_frontend,
            )
        samples = []
        for chunk in generated: samples.extend(flatten_samples(chunk["tts_speech"]))
        write_wav(output_path, samples, loaded.sample_rate, volume)
    elif runtime == "sherpaOnnx":
        import sherpa_onnx
        generation = sherpa_onnx.GenerationConfig()
        generation.sid = int(config.get("speaker_id", 3))
        generation.speed = float(config.get("speed", 1.0))
        generation.silence_scale = float(config.get("silence_scale", 1.0))
        audio = loaded.generate(text, generation)
        write_wav(output_path, audio.samples, audio.sample_rate, volume)
    else:
        raise RuntimeError("当前运行时不支持语音合成")
    return output_path

def respond(request_id, result=None, error=None):
    payload = {"id": request_id, "ok": error is None}
    if error is None: payload["result"] = result or {}
    else: payload["error"] = error
    encoded = base64.urlsafe_b64encode(
        json.dumps(payload, ensure_ascii=False).encode("utf-8")
    ).decode("ascii")
    print("OPENHAND_响应 " + encoded, flush=True)

def handle_request(runtime, loaded, config, request):
    operation = request.get("operation")
    if operation == "recognize":
        transcript = recognize(runtime, loaded, request["audio_path"], config)
        return {"transcript": transcript}
    if operation == "synthesize":
        path = synthesize(
            runtime, loaded, request["text"], request["output_path"], config
        )
        return {"audio_path": path}
    raise RuntimeError("不支持的测试操作")

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
    for line in sys.stdin:
        line = line.strip()
        if not line: continue
        request_id = ""
        try:
            request = json.loads(base64.urlsafe_b64decode(line).decode("utf-8"))
            request_id = str(request.get("id", ""))
            respond(request_id, result=handle_request(args.runtime, loaded, config, request))
        except Exception as error:
            details = traceback.format_exc().strip().splitlines()
            respond(request_id, error=str(error) + "\n" + "\n".join(details[-8:]))

try:
    main()
except KeyboardInterrupt:
    pass
except Exception:
    traceback.print_exc()
    sys.exit(1)
''';

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:charset_converter/charset_converter.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../../app/support/openhand_paths.dart';
import '../../../../app/support/safe_subprocess.dart';
import '../../../../app/support/system_proxy.dart';
import '../../../../shared/util/async_concurrency.dart';
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

class OfflineSpeechTestCancelled implements Exception {
  const OfflineSpeechTestCancelled();

  @override
  String toString() => '模型测试已终止。';
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

class OfflineSpeechAudioStream {
  OfflineSpeechAudioStream._({
    required this.sampleRate,
    required this.channels,
    required this.audio,
    required this.done,
    required this._addText,
    required this._finish,
    required this._close,
  });

  final int sampleRate;
  final int channels;
  final Stream<Uint8List> audio;
  final Future<void> done;
  final void Function(String text) _addText;
  final Future<void> Function() _finish;
  final Future<void> Function() _close;

  void addText(String text) => _addText(text);
  Future<void> finish() => _finish();
  Future<void> close() => _close();
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

  static OfflineSpeechModelService? _sharedInstance;

  static OfflineSpeechModelService get instance =>
      _sharedInstance ??= OfflineSpeechModelService._();

  static Future<void> shutdownInstance() async {
    await _sharedInstance?.shutdown();
  }

  static const Duration runtimeCleanupTimeout =
      kOpenHandServiceRuntimeCleanupTimeout;
  static const String testSampleText = '你好，这是一段 OpenHand 语音朗读测试。';
  static const Duration _runtimeStartTimeout = Duration(minutes: 5);
  static const Duration _inferenceTimeout = Duration(minutes: 5);
  static const Duration _realtimeConnectTimeout = Duration(seconds: 10);
  static const Duration _realtimeStartTimeout = Duration(seconds: 30);
  static const Duration _realtimeCloseTimeout = Duration(seconds: 2);
  static const Duration _runtimeInstallTimeout = Duration(minutes: 45);
  static const Duration _downloadNotifyInterval = Duration(milliseconds: 80);
  static const Duration _downloadIdleTimeout = Duration(seconds: 60);
  static const Duration _onlineAudioFrameInterval = Duration(milliseconds: 40);
  static const Duration _onlineIdleTimeout = Duration(seconds: 30);
  static const int _runtimeNetworkAttempts = 2;
  static const int _runtimeErrorCharacters = 8 * 1024;
  static const int _onlineAudioFrameBytes = 1280;
  static const int _maxOnlineAudioBytes = 64 * 1024 * 1024;
  static const int _maxOnlineEventCharacters = 16 * 1024 * 1024;
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
      revision: 'cosyvoice-074ca6d-v5',
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
        'websockets==12.0',
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
  final Set<Future<void>> _activeStarts = <Future<void>>{};
  final Set<Future<OfflineSpeechTestResult>> _activeTests =
      <Future<OfflineSpeechTestResult>>{};
  final Map<OfflineSpeechAudioStream, String> _activeAudioStreams =
      <OfflineSpeechAudioStream, String>{};
  final Completer<void> _shutdownSignal = Completer<void>();
  final OpenHandAsyncOnce _shutdownOnce = OpenHandAsyncOnce();
  bool _shuttingDown = false;
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
    if (model.isOnline) return _onlineAvailability(model, configuration);
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

  OfflineSpeechModelAvailability _onlineAvailability(
    OfflineSpeechModelDefinition model,
    Map<String, Object?> configuration,
  ) {
    final endpoint = Uri.tryParse(
      _configurationText(configuration, 'endpoint'),
    );
    if (endpoint == null ||
        endpoint.scheme != 'wss' ||
        endpoint.host.trim().isEmpty) {
      return const OfflineSpeechModelAvailability(
        available: false,
        reason: '请填写有效的 WSS 服务地址。',
      );
    }
    final missing = <String>[];
    void require(String key, String label) {
      if (_configurationText(configuration, key).isEmpty) missing.add(label);
    }

    switch (model.onlineService) {
      case OnlineSpeechService.xfyunRtasr:
        require('appid', 'APPID');
        require('api_key', 'APIKey');
      case OnlineSpeechService.xfyunRtasrLlm:
        require('app_id', 'App ID');
        require('access_key_id', 'AccessKey ID');
        require('access_key_secret', 'AccessKey Secret');
        if (_configurationText(configuration, 'audio_encode') != 'pcm_s16le') {
          return const OfflineSpeechModelAvailability(
            available: false,
            reason: '当前麦克风输入为 PCM，请将音频编码设为 PCM 16-bit。',
          );
        }
      case OnlineSpeechService.xfyunTts:
        require('app_id', 'APPID');
        final audioEncoding = _configurationText(configuration, 'aue');
        final sampleRate = _configurationText(configuration, 'auf');
        if (audioEncoding == 'lame' &&
            !_configurationBool(configuration, 'sfl')) {
          return const OfflineSpeechModelAvailability(
            available: false,
            reason: 'MP3 编码必须开启 MP3 流式返回。',
          );
        }
        final requires8k =
            audioEncoding == 'opus' ||
            audioEncoding == 'speex' ||
            audioEncoding == 'speex-org-nb';
        final requires16k =
            audioEncoding == 'opus-wb' ||
            audioEncoding == 'speex-wb' ||
            audioEncoding == 'speex-org-wb';
        if ((requires8k && !sampleRate.contains('8000')) ||
            (requires16k && !sampleRate.contains('16000'))) {
          return OfflineSpeechModelAvailability(
            available: false,
            reason: requires8k
                ? '当前音频编码需要选择 8 kHz 采样率。'
                : '当前音频编码需要选择 16 kHz 采样率。',
          );
        }
        if (_configurationText(configuration, 'auth_mode') == 'api_password') {
          require('api_password', 'API Password');
        } else {
          require('api_key', 'APIKey');
          require('api_secret', 'APISecret');
        }
      case null:
        return const OfflineSpeechModelAvailability(
          available: false,
          reason: '在线语音服务类型无效。',
        );
    }
    if (missing.isNotEmpty) {
      return OfflineSpeechModelAvailability(
        available: false,
        reason: '请补全讯飞配置：${missing.join('、')}。',
      );
    }
    return const OfflineSpeechModelAvailability(
      available: true,
      reason: '在线服务配置完整，将通过加密 WebSocket 连接讯飞。',
    );
  }

  String modelDirectory(OfflineSpeechModelDefinition model) =>
      p.join(modelsRoot, model.id);

  bool isRunning(OfflineSpeechModelDefinition model) =>
      !model.isOnline && _processes.containsKey(model.id);

  bool isRuntimeReady(OfflineSpeechModelDefinition model) =>
      model.isOnline ||
      (isRunning(model) &&
          stateOf(model).lifecycle == OfflineSpeechLifecycle.running);

  OfflineSpeechModelState stateOf(OfflineSpeechModelDefinition model) {
    if (model.isOnline) {
      return const OfflineSpeechModelState(
        lifecycle: OfflineSpeechLifecycle.installed,
      );
    }
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
    if (model.isOnline) return true;
    return File(
      p.join(modelDirectory(model), 'openhand-model.json'),
    ).existsSync();
  }

  bool requiresDownloadForConfiguration(
    OfflineSpeechModelDefinition model,
    Map<String, Object?> configuration,
  ) {
    if (model.isOnline) return false;
    return requiresModelFilesForConfiguration(model, configuration) ||
        requiresRuntimePreparation(model);
  }

  bool requiresModelFilesForConfiguration(
    OfflineSpeechModelDefinition model,
    Map<String, Object?> configuration,
  ) {
    if (model.isOnline) return false;
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
    if (model.isOnline) return false;
    return !_isRuntimeReady(model.runtime);
  }

  String runtimePreparationSizeLabel(OfflineSpeechModelDefinition model) {
    if (model.isOnline) return '无需本地运行环境';
    final size = _runtimeSpecs[model.runtime]!.estimatedStorageGiB;
    return '约 ${size == size.roundToDouble() ? size.toInt() : size} GB';
  }

  Future<void> download(
    OfflineSpeechModelDefinition model,
    Map<String, Object?> configuration,
  ) async {
    if (model.isOnline) return;
    _throwIfShuttingDown();
    if (_downloadCancellations.containsKey(model.id)) return;
    await SystemProxyResolver.instance.initialize();
    _throwIfShuttingDown();
    await _inspectHardware();
    _throwIfShuttingDown();
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
      cancellation.finish();
    }
  }

  void cancelDownload(OfflineSpeechModelDefinition model) {
    _downloadCancellations[model.id]?.cancel();
  }

  Future<void> remove(OfflineSpeechModelDefinition model) async {
    if (model.isOnline) return;
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
    Map<String, Object?> configuration, {
    Future<void>? cancelSignal,
  }) {
    late final Future<void> operation;
    operation = _start(
      model,
      configuration,
      cancelSignal: cancelSignal,
    ).whenComplete(() => _activeStarts.remove(operation));
    _activeStarts.add(operation);
    return operation;
  }

  Future<void> _start(
    OfflineSpeechModelDefinition model,
    Map<String, Object?> configuration, {
    Future<void>? cancelSignal,
  }) async {
    _throwIfShuttingDown();
    final effectiveCancelSignal = combineCancelSignals(<Future<void>?>[
      cancelSignal,
      _shutdownSignal.future,
    ]);
    if (await isCancelSignalCompleted(effectiveCancelSignal)) {
      throw const OfflineSpeechTestCancelled();
    }
    if (model.isOnline) {
      final availability = availabilityFor(model, configuration);
      if (!availability.available) throw StateError(availability.reason);
      return;
    }
    await _inspectHardware();
    if (await isCancelSignalCompleted(effectiveCancelSignal)) {
      throw const OfflineSpeechTestCancelled();
    }
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
    if (await isCancelSignalCompleted(effectiveCancelSignal)) {
      throw const OfflineSpeechTestCancelled();
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
      if (await isCancelSignalCompleted(effectiveCancelSignal)) {
        throw const OfflineSpeechTestCancelled();
      }
      process = await _runtimeAdapters[model.runtime]!.start(
        pythonExecutable: python,
        runnerPath: runner.path,
        model: model,
        modelPath: modelDirectory(model),
        configuration: configuration,
        workingDirectory: runtimeRoot,
        environment: _runtimeEnvironment(model.runtime, runtimeRoot),
      );
      if (await isCancelSignalCompleted(effectiveCancelSignal)) {
        throw const OfflineSpeechTestCancelled();
      }
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
      final ready = await awaitWithCancelSignal<bool>(
        startedSession.ready.future.then((_) => true),
        cancelSignal: effectiveCancelSignal,
      ).timeout(_runtimeStartTimeout);
      if (ready != true) throw const OfflineSpeechTestCancelled();
      if (model.synthesisTransport ==
              OfflineSpeechSynthesisTransport.webSocket &&
          startedSession.realtimeEndpoint == null) {
        throw StateError('模型实时语音通道启动失败。');
      }
      _setState(
        model.id,
        const OfflineSpeechModelState(
          lifecycle: OfflineSpeechLifecycle.running,
        ),
      );
    } catch (error) {
      _processes.remove(model.id);
      if (process != null) {
        await terminateTrackedProcessTree(process);
      }
      if (error is! OfflineSpeechTestCancelled &&
          _isRuntimeDependencyFailure(error)) {
        await _invalidateRuntime(model.runtime);
      }
      _setState(
        model.id,
        OfflineSpeechModelState(
          lifecycle: error is OfflineSpeechTestCancelled
              ? OfflineSpeechLifecycle.installed
              : OfflineSpeechLifecycle.failed,
          message: error is OfflineSpeechTestCancelled ? null : '$error',
        ),
      );
      rethrow;
    }
  }

  Future<void> stop(OfflineSpeechModelDefinition model) async {
    final audioStreams = _activeAudioStreams.entries
        .where((entry) => entry.value == model.id)
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final stream in audioStreams) {
      _activeAudioStreams.remove(stream);
      await stream.close();
    }
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
    await terminateTrackedProcessTree(session.process);
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
    Future<void>? cancelSignal,
    bool startIfNeeded = true,
  }) {
    late final Future<OfflineSpeechTestResult> operation;
    operation = _test(
      model,
      configuration,
      audioPath: audioPath,
      sampleText: sampleText,
      cancelSignal: cancelSignal,
      startIfNeeded: startIfNeeded,
    ).whenComplete(() => _activeTests.remove(operation));
    _activeTests.add(operation);
    return operation;
  }

  bool supportsRealtimeSynthesis(
    OfflineSpeechModelDefinition model,
    Map<String, Object?> configuration,
  ) {
    if (model.kind != OfflineSpeechKind.synthesis ||
        model.synthesisTransport != OfflineSpeechSynthesisTransport.webSocket) {
      return false;
    }
    return model.onlineService != OnlineSpeechService.xfyunTts ||
        _configurationText(configuration, 'aue') == 'raw';
  }

  Future<OfflineSpeechAudioStream> streamSynthesis(
    OfflineSpeechModelDefinition model,
    String text, {
    required Map<String, Object?> configuration,
    Future<void>? cancelSignal,
  }) async {
    final stream = await startSynthesisStream(
      model,
      configuration: configuration,
      cancelSignal: cancelSignal,
    );
    try {
      stream.addText(text);
      await stream.finish();
      return stream;
    } catch (_) {
      await stream.close();
      rethrow;
    }
  }

  Future<OfflineSpeechAudioStream> startSynthesisStream(
    OfflineSpeechModelDefinition model, {
    required Map<String, Object?> configuration,
    Future<void>? cancelSignal,
  }) async {
    _throwIfShuttingDown();
    if (model.kind != OfflineSpeechKind.synthesis ||
        !supportsRealtimeSynthesis(model, configuration)) {
      throw StateError('当前朗读模型不支持实时语音通道。');
    }
    if (model.onlineService == OnlineSpeechService.xfyunTts) {
      final availability = availabilityFor(model, configuration);
      if (!availability.available) throw StateError(availability.reason);
      return _startXfyunSynthesisStream(
        model,
        configuration,
        cancelSignal: combineCancelSignals(<Future<void>?>[
          cancelSignal,
          _shutdownSignal.future,
        ]),
      );
    }
    final session = _processes[model.id];
    if (session == null) throw StateError('模型运行时尚未就绪。');
    final endpoint = session.realtimeEndpoint;
    if (endpoint == null) throw StateError('模型实时语音通道尚未就绪。');
    final stream = await _openRealtimeSpeechStream(
      endpoint,
      cancelSignal: combineCancelSignals(<Future<void>?>[
        cancelSignal,
        _shutdownSignal.future,
      ]),
    );
    _activeAudioStreams[stream] = model.id;
    unawaited(
      stream.done.then<void>(
        (_) => _activeAudioStreams.remove(stream),
        onError: (Object _, StackTrace _) => _activeAudioStreams.remove(stream),
      ),
    );
    return stream;
  }

  Future<OfflineSpeechAudioStream> _openRealtimeSpeechStream(
    Uri endpoint, {
    Future<void>? cancelSignal,
  }) async {
    final client = HttpClient()..findProxy = (_) => 'DIRECT';
    final connectionFuture = WebSocket.connect(
      endpoint.toString(),
      customClient: client,
    ).timeout(_realtimeConnectTimeout);
    WebSocket? socket;
    try {
      socket = await awaitWithCancelSignal<WebSocket>(
        connectionFuture,
        cancelSignal: cancelSignal,
      );
    } catch (_) {
      client.close(force: true);
      rethrow;
    }
    if (socket == null) {
      unawaited(
        connectionFuture.then<void>((lateSocket) async {
          await lateSocket.close();
          client.close(force: true);
        }, onError: (Object _, StackTrace _) => client.close(force: true)),
      );
      throw const OfflineSpeechTestCancelled();
    }
    final activeSocket = socket;
    final audio = StreamController<Uint8List>();
    final started = Completer<(int, int)>();
    final done = Completer<void>();
    StreamSubscription<dynamic>? subscription;
    var closed = false;
    var finished = false;

    Future<void> close() async {
      if (closed) return;
      closed = true;
      try {
        await subscription?.cancel().timeout(_realtimeCloseTimeout);
      } catch (_) {}
      try {
        await activeSocket
            .close(WebSocketStatus.normalClosure)
            .timeout(_realtimeCloseTimeout);
      } catch (_) {}
      client.close(force: true);
      if (!audio.isClosed) await audio.close();
      if (!started.isCompleted) {
        started.completeError(const OfflineSpeechTestCancelled());
      }
      if (!done.isCompleted) done.complete();
    }

    void fail(Object error, [StackTrace? stack]) {
      final streamStarted = started.isCompleted;
      if (!started.isCompleted) {
        stack == null
            ? started.completeError(error)
            : started.completeError(error, stack);
      }
      if (!audio.isClosed) {
        audio.addError(error, stack);
        unawaited(audio.close());
      }
      if (!done.isCompleted) {
        if (!streamStarted) {
          done.complete();
        } else {
          stack == null
              ? done.completeError(error)
              : done.completeError(error, stack);
        }
      }
    }

    void addText(String text) {
      final source = text.trim();
      if (source.isEmpty) return;
      if (closed || finished) throw StateError('实时语音通道已结束。');
      activeSocket.add(
        jsonEncode(<String, Object?>{'type': 'text', 'text': source}),
      );
    }

    Future<void> finish() async {
      if (closed || finished) return;
      finished = true;
      activeSocket.add(jsonEncode(const <String, Object?>{'type': 'finish'}));
    }

    subscription = activeSocket.listen(
      (event) {
        if (event is List<int>) {
          if (!started.isCompleted || closed || event.isEmpty) return;
          audio.add(Uint8List.fromList(event));
          return;
        }
        if (event is! String) return;
        try {
          final payload = jsonDecode(event);
          if (payload is! Map) throw const FormatException('消息格式无效。');
          switch ('${payload['type'] ?? ''}') {
            case 'start':
              final sampleRate = payload['sample_rate'];
              final channels = payload['channels'];
              if (sampleRate is! num ||
                  sampleRate < 8000 ||
                  sampleRate > 192000 ||
                  channels is! num ||
                  channels < 1 ||
                  channels > 8) {
                throw const FormatException('音频参数无效。');
              }
              if (!started.isCompleted) {
                started.complete((sampleRate.toInt(), channels.toInt()));
              }
            case 'end':
              if (!audio.isClosed) unawaited(audio.close());
              if (!done.isCompleted) done.complete();
              unawaited(activeSocket.close(WebSocketStatus.normalClosure));
            case 'error':
              fail(StateError('${payload['message'] ?? '实时语音生成失败。'}'));
              unawaited(
                activeSocket.close(WebSocketStatus.internalServerError),
              );
          }
        } catch (error, stack) {
          fail(StateError('无法解析实时语音响应：$error'), stack);
          unawaited(
            activeSocket.close(WebSocketStatus.invalidFramePayloadData),
          );
        }
      },
      onError: (Object error, StackTrace stack) => fail(error, stack),
      onDone: () {
        if (!closed && !done.isCompleted) {
          fail(StateError('实时语音连接意外中断。'));
        }
      },
    );
    if (cancelSignal != null) {
      unawaited(cancelSignal.then<void>((_) => close()));
    }
    activeSocket.add(
      jsonEncode(const <String, Object?>{'operation': 'synthesize_stream'}),
    );
    try {
      final format = await awaitWithCancelSignal<(int, int)>(
        started.future,
        cancelSignal: cancelSignal,
      ).timeout(_realtimeStartTimeout);
      if (format == null) throw const OfflineSpeechTestCancelled();
      return OfflineSpeechAudioStream._(
        sampleRate: format.$1,
        channels: format.$2,
        audio: audio.stream,
        done: done.future,
        addText: addText,
        finish: finish,
        close: close,
      );
    } catch (_) {
      await close();
      rethrow;
    }
  }

  Future<OfflineSpeechTestResult> _test(
    OfflineSpeechModelDefinition model,
    Map<String, Object?> configuration, {
    String? audioPath,
    required String sampleText,
    Future<void>? cancelSignal,
    required bool startIfNeeded,
  }) async {
    _throwIfShuttingDown();
    final effectiveCancelSignal = combineCancelSignals(<Future<void>?>[
      cancelSignal,
      _shutdownSignal.future,
    ]);
    if (model.isOnline) {
      final availability = availabilityFor(model, configuration);
      if (!availability.available) throw StateError(availability.reason);
      return _testOnline(
        model,
        configuration,
        audioPath: audioPath,
        sampleText: sampleText,
        cancelSignal: effectiveCancelSignal,
      );
    }
    final wasRunning = _processes.containsKey(model.id);
    if (!wasRunning) {
      if (!startIfNeeded) throw StateError('模型尚未运行。');
      await start(model, configuration, cancelSignal: effectiveCancelSignal);
    }
    Directory? outputDirectory;
    try {
      final session = _processes[model.id];
      if (session == null) throw StateError('模型运行时尚未就绪。');
      if (model.kind == OfflineSpeechKind.recognition) {
        final source = audioPath?.trim() ?? '';
        if (source.isEmpty || !await File(source).exists()) {
          throw StateError('没有可识别的录音文件。');
        }
        final response = await session.request(
          <String, Object?>{'operation': 'recognize', 'audio_path': source},
          timeout: _inferenceTimeout,
          cancelSignal: effectiveCancelSignal,
        );
        return OfflineSpeechTestResult.recognition(
          '${response['transcript'] ?? ''}'.trim(),
        );
      }
      outputDirectory = await Directory.systemTemp.createTemp(
        'openhand_speech_test_',
      );
      final outputPath = p.join(outputDirectory.path, 'sample.wav');
      if (model.synthesisTransport ==
          OfflineSpeechSynthesisTransport.webSocket) {
        final stream = await streamSynthesis(
          model,
          sampleText,
          configuration: configuration,
          cancelSignal: effectiveCancelSignal,
        );
        final pcm = BytesBuilder(copy: false);
        try {
          await for (final chunk in stream.audio) {
            pcm.add(chunk);
          }
          await stream.done;
        } finally {
          await stream.close();
        }
        final bytes = pcm.takeBytes();
        if (bytes.isEmpty) throw StateError('模型没有生成有效音频。');
        await File(outputPath).writeAsBytes(
          _pcm16Wav(bytes, stream.sampleRate, stream.channels),
          flush: true,
        );
        return OfflineSpeechTestResult.synthesis(outputPath);
      }
      final response = await session.request(
        <String, Object?>{
          'operation': 'synthesize',
          'text': sampleText,
          'output_path': outputPath,
        },
        timeout: _inferenceTimeout,
        cancelSignal: effectiveCancelSignal,
        onDiscardedResponse: () =>
            unawaited(_deleteTemporaryDirectory(outputDirectory)),
      );
      final generatedPath = '${response['audio_path'] ?? ''}'.trim();
      final generated = File(generatedPath);
      if (generatedPath.isEmpty ||
          !await generated.exists() ||
          await generated.length() == 0) {
        throw StateError('模型没有生成有效音频。');
      }
      return OfflineSpeechTestResult.synthesis(generatedPath);
    } catch (error) {
      await _deleteTemporaryDirectory(outputDirectory);
      rethrow;
    } finally {
      if (!wasRunning) await stop(model);
    }
  }

  Future<OfflineSpeechTestResult> _testOnline(
    OfflineSpeechModelDefinition model,
    Map<String, Object?> configuration, {
    String? audioPath,
    required String sampleText,
    Future<void>? cancelSignal,
  }) async {
    switch (model.onlineService) {
      case OnlineSpeechService.xfyunRtasr:
      case OnlineSpeechService.xfyunRtasrLlm:
        final source = audioPath?.trim() ?? '';
        if (source.isEmpty || !await File(source).exists()) {
          throw StateError('没有可识别的录音文件。');
        }
        final wav = await _readPcm16Wav(source);
        var pcm = wav.pcm;
        var sampleRate = wav.sampleRate;
        if (model.onlineService == OnlineSpeechService.xfyunRtasrLlm &&
            _configurationText(configuration, 'samplerate') == '8000') {
          pcm = _downsamplePcm16(pcm, from: sampleRate, to: 8000);
          sampleRate = 8000;
        }
        if (sampleRate != 16000 &&
            model.onlineService == OnlineSpeechService.xfyunRtasr) {
          throw StateError('讯飞实时语音转写标准版仅支持 16 kHz PCM 音频。');
        }
        final transcript = await _recognizeWithXfyun(
          model,
          configuration,
          pcm,
          sampleRate: sampleRate,
          cancelSignal: cancelSignal,
        );
        return OfflineSpeechTestResult.recognition(transcript);
      case OnlineSpeechService.xfyunTts:
        final generated = await _synthesizeXfyunText(
          configuration,
          sampleText,
          cancelSignal: cancelSignal,
        );
        if (generated.bytes.isEmpty) throw StateError('讯飞没有返回有效音频。');
        final directory = await Directory.systemTemp.createTemp(
          'openhand_speech_test_',
        );
        final path = p.join(directory.path, 'sample${generated.extension}');
        final bytes = generated.extension == '.pcm'
            ? _pcm16Wav(generated.bytes, generated.sampleRate, 1)
            : generated.bytes;
        final outputPath = generated.extension == '.pcm'
            ? p.join(directory.path, 'sample.wav')
            : path;
        await File(outputPath).writeAsBytes(bytes, flush: true);
        return OfflineSpeechTestResult.synthesis(outputPath);
      case null:
        throw StateError('在线语音服务类型无效。');
    }
  }

  Future<OfflineSpeechAudioStream> _startXfyunSynthesisStream(
    OfflineSpeechModelDefinition model,
    Map<String, Object?> configuration, {
    Future<void>? cancelSignal,
  }) async {
    final audio = StreamController<Uint8List>();
    final done = Completer<void>();
    final localCancellation = Completer<void>();
    final queue = <String>[];
    final sampleRate = _xfyunSampleRate(configuration);
    var processing = false;
    var finishing = false;
    var closed = false;

    void fail(Object error, StackTrace stack) {
      if (!audio.isClosed) {
        audio.addError(error, stack);
        unawaited(audio.close());
      }
      if (!done.isCompleted) done.completeError(error, stack);
    }

    Future<void> pump() async {
      if (processing || closed) return;
      processing = true;
      try {
        while (queue.isNotEmpty && !closed) {
          final text = queue.removeAt(0);
          await _synthesizeXfyunText(
            configuration,
            text,
            cancelSignal: combineCancelSignals(<Future<void>?>[
              cancelSignal,
              localCancellation.future,
            ]),
            onAudio: (chunk) {
              if (!closed && !audio.isClosed) audio.add(chunk);
            },
          );
        }
        if (finishing && !closed) {
          if (!audio.isClosed) await audio.close();
          if (!done.isCompleted) done.complete();
        }
      } catch (error, stack) {
        if (!closed) fail(error, stack);
      } finally {
        processing = false;
        if (queue.isNotEmpty && !closed) unawaited(pump());
      }
    }

    void addText(String text) {
      final source = text.trim();
      if (source.isEmpty) return;
      if (closed || finishing) throw StateError('实时语音通道已结束。');
      if (queue.length >= 256) throw StateError('待朗读文本队列已满。');
      queue.add(source);
      unawaited(pump());
    }

    Future<void> finish() async {
      if (closed || finishing) return;
      finishing = true;
      await pump();
      await done.future;
    }

    Future<void> close() async {
      if (closed) return;
      closed = true;
      queue.clear();
      if (!localCancellation.isCompleted) localCancellation.complete();
      if (!audio.isClosed) await audio.close();
      if (!done.isCompleted) done.complete();
    }

    final stream = OfflineSpeechAudioStream._(
      sampleRate: sampleRate,
      channels: 1,
      audio: audio.stream,
      done: done.future,
      addText: addText,
      finish: finish,
      close: close,
    );
    _activeAudioStreams[stream] = model.id;
    unawaited(
      stream.done.then<void>(
        (_) => _activeAudioStreams.remove(stream),
        onError: (Object _, StackTrace _) => _activeAudioStreams.remove(stream),
      ),
    );
    if (cancelSignal != null) {
      unawaited(cancelSignal.then<void>((_) => close()));
    }
    return stream;
  }

  Future<String> _recognizeWithXfyun(
    OfflineSpeechModelDefinition model,
    Map<String, Object?> configuration,
    Uint8List pcm, {
    required int sampleRate,
    Future<void>? cancelSignal,
  }) async {
    await SystemProxyResolver.instance.initialize();
    final endpoint = Uri.parse(_configurationText(configuration, 'endpoint'));
    final largeModel = model.onlineService == OnlineSpeechService.xfyunRtasrLlm;
    final uuid = _configurationText(configuration, 'uuid').isEmpty
        ? const Uuid().v4()
        : _configurationText(configuration, 'uuid');
    final parameters = largeModel
        ? _xfyunLlmRecognitionParameters(
            endpoint,
            configuration,
            uuid,
            sampleRate,
          )
        : _xfyunStandardRecognitionParameters(endpoint, configuration);
    final uri = endpoint.replace(queryParameters: parameters);
    final client = SystemProxyResolver.instance.createRawHttpClient(
      connectionTimeout: _onlineIdleTimeout,
    );
    WebSocket? socket;
    try {
      final connecting = WebSocket.connect(
        uri.toString(),
        customClient: client,
      ).timeout(_onlineIdleTimeout);
      socket = await awaitWithCancelSignal<WebSocket>(
        connecting,
        cancelSignal: cancelSignal,
      );
      if (socket == null) throw const OfflineSpeechTestCancelled();
      final activeSocket = socket;
      final completed = SplayTreeMap<int, String>();
      final partial = SplayTreeMap<int, String>();

      Future<void> receive() async {
        await for (final event in activeSocket.timeout(_onlineIdleTimeout)) {
          if (event is! String) continue;
          if (event.length > _maxOnlineEventCharacters) {
            throw const FormatException('讯飞语音识别响应超过安全上限。');
          }
          final payload = jsonDecode(event);
          if (payload is! Map) continue;
          if (_consumeXfyunRecognitionPayload(payload, completed, partial)) {
            break;
          }
        }
      }

      final receiving = receive();
      for (
        var offset = 0;
        offset < pcm.length;
        offset += _onlineAudioFrameBytes
      ) {
        if (offset > 0) {
          final waited = await awaitWithCancelSignal<bool>(
            Future<bool>.delayed(_onlineAudioFrameInterval, () => true),
            cancelSignal: cancelSignal,
          );
          if (waited != true) throw const OfflineSpeechTestCancelled();
        }
        final end = math.min(offset + _onlineAudioFrameBytes, pcm.length);
        activeSocket.add(pcm.sublist(offset, end));
      }
      activeSocket.add(
        utf8.encode(
          largeModel
              ? jsonEncode(<String, Object?>{'end': true, 'sessionId': uuid})
              : jsonEncode(const <String, Object?>{'end': true}),
        ),
      );
      final received = await awaitWithCancelSignal<bool>(
        receiving.then((_) => true),
        cancelSignal: cancelSignal,
      ).timeout(_inferenceTimeout);
      if (received != true) throw const OfflineSpeechTestCancelled();
      final keys = <int>{...completed.keys, ...partial.keys}.toList()..sort();
      return keys
          .map((key) => completed[key] ?? partial[key] ?? '')
          .join()
          .trim();
    } finally {
      try {
        await socket
            ?.close(WebSocketStatus.normalClosure)
            .timeout(_realtimeCloseTimeout);
      } catch (_) {}
      client.close(force: true);
    }
  }

  Map<String, String> _xfyunStandardRecognitionParameters(
    Uri endpoint,
    Map<String, Object?> configuration,
  ) {
    final appId = _configurationText(configuration, 'appid');
    final apiKey = _configurationText(configuration, 'api_key');
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final digest = md5.convert(utf8.encode('$appId$timestamp')).toString();
    final signature = base64Encode(
      Hmac(sha1, utf8.encode(apiKey)).convert(utf8.encode(digest)).bytes,
    );
    final parameters = <String, String>{
      ...endpoint.queryParameters,
      'appid': appId,
      'ts': '$timestamp',
      'signa': signature,
      'lang': _configurationText(configuration, 'lang'),
      'vadMdn': _configurationText(configuration, 'vad_mdn'),
      'roleType': _configurationText(configuration, 'role_type'),
      'engLangType': _configurationText(configuration, 'eng_lang_type'),
    };
    final targetLanguage = _configurationText(configuration, 'target_lang');
    if (targetLanguage.isNotEmpty) {
      parameters.addAll(<String, String>{
        'transType': _configurationText(configuration, 'trans_type'),
        'transStrategy': _configurationText(configuration, 'trans_strategy'),
        'targetLang': targetLanguage,
      });
    }
    _addNonEmptyParameter(parameters, 'punc', configuration, 'punc');
    _addNonEmptyParameter(parameters, 'pd', configuration, 'pd');
    return parameters;
  }

  Map<String, String> _xfyunLlmRecognitionParameters(
    Uri endpoint,
    Map<String, Object?> configuration,
    String uuid,
    int sampleRate,
  ) {
    final now = DateTime.now().toUtc();
    final utc =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}T'
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}+0000';
    final parameters = <String, String>{
      ...endpoint.queryParameters,
      'appId': _configurationText(configuration, 'app_id'),
      'accessKeyId': _configurationText(configuration, 'access_key_id'),
      'uuid': uuid,
      'utc': utc,
      'lang': _configurationText(configuration, 'lang'),
      'audio_encode': 'pcm_s16le',
      'samplerate': '$sampleRate',
      'role_type': _configurationText(configuration, 'role_type'),
      'eng_spk_match': _configurationText(configuration, 'eng_spk_match'),
      'eng_vad_mdn': _configurationText(configuration, 'eng_vad_mdn'),
    };
    if (parameters['lang'] == 'autominor') {
      _addNonEmptyParameter(
        parameters,
        'recognized_language',
        configuration,
        'recognized_language',
      );
    }
    _addNonEmptyParameter(
      parameters,
      'feature_ids',
      configuration,
      'feature_ids',
    );
    _addNonEmptyParameter(parameters, 'pd', configuration, 'pd');
    _addNonEmptyParameter(parameters, 'eng_punc', configuration, 'eng_punc');
    final sortedQuery = _sortedQuery(parameters);
    parameters['signature'] = base64Encode(
      Hmac(
        sha1,
        utf8.encode(_configurationText(configuration, 'access_key_secret')),
      ).convert(utf8.encode(sortedQuery)).bytes,
    );
    return parameters;
  }

  bool _consumeXfyunRecognitionPayload(
    Map payload,
    SplayTreeMap<int, String> completed,
    SplayTreeMap<int, String> partial,
  ) {
    final code = '${payload['code'] ?? '0'}';
    final action = '${payload['action'] ?? ''}';
    if ((action == 'error' || code != '0') && code != 'null') {
      throw StateError(
        '讯飞语音识别失败（$code）：${payload['desc'] ?? payload['message'] ?? '未知错误'}',
      );
    }
    Object? data = payload['data'];
    if (data is String && data.trim().isNotEmpty) {
      data = jsonDecode(data);
    }
    if (data is! Map) return false;
    if (data['biz'] == 'trans') {
      final segment = _integerValue(data['segId']);
      final text = '${data['dst'] ?? data['src'] ?? ''}'.trim();
      final finalResult = _integerValue(data['type']) == 0;
      (finalResult ? completed : partial)[segment] = text;
      if (finalResult) partial.remove(segment);
      return data['isEnd'] == true;
    }
    final segment = _integerValue(data['seg_id']);
    final st = data['cn'] is Map ? (data['cn'] as Map)['st'] : null;
    if (st is Map) {
      final text = _xfyunRecognitionWords(st['rt']);
      final finalResult = '${st['type'] ?? '1'}' == '0';
      (finalResult ? completed : partial)[segment] = text;
      if (finalResult) partial.remove(segment);
    }
    return data['ls'] == true;
  }

  String _xfyunRecognitionWords(Object? raw) {
    if (raw is! List) return '';
    final output = StringBuffer();
    for (final result in raw) {
      if (result is! Map || result['ws'] is! List) continue;
      for (final word in result['ws'] as List) {
        if (word is! Map ||
            word['cw'] is! List ||
            (word['cw'] as List).isEmpty) {
          continue;
        }
        final candidate = (word['cw'] as List).first;
        if (candidate is! Map) continue;
        final role = _integerValue(candidate['rl']);
        if (role > 0) {
          if (output.isNotEmpty) output.write('\n');
          output.write('说话人$role：');
        }
        output.write('${candidate['w'] ?? ''}');
      }
    }
    return output.toString();
  }

  Future<({Uint8List bytes, int sampleRate, String extension})>
  _synthesizeXfyunText(
    Map<String, Object?> configuration,
    String text, {
    Future<void>? cancelSignal,
    void Function(Uint8List chunk)? onAudio,
  }) async {
    final source = text.trim();
    if (source.isEmpty) throw StateError('没有可合成的文本。');
    final encoding = _configurationText(configuration, 'tte');
    late final Uint8List encodedText;
    try {
      encodedText = await CharsetConverter.encode(
        _xfyunCharsetName(encoding),
        source,
      );
    } catch (_) {
      throw StateError('当前系统不支持 $encoding 文本编码，请改用 UTF-8。');
    }
    if (encodedText.length >= 8000) {
      throw StateError('讯飞单次合成文本必须小于 8000 字节。');
    }
    await SystemProxyResolver.instance.initialize();
    var endpoint = Uri.parse(_configurationText(configuration, 'endpoint'));
    final binaryOutput = _configurationBool(configuration, 'binary_output');
    if (binaryOutput) {
      endpoint = endpoint.replace(
        queryParameters: <String, String>{
          ...endpoint.queryParameters,
          'output_proto': 'binary',
        },
      );
    }
    final headers = <String, dynamic>{};
    if (_configurationText(configuration, 'auth_mode') == 'api_password') {
      headers['x-api-key'] = _configurationText(configuration, 'api_password');
    } else {
      endpoint = _xfyunTtsAuthorizedUri(endpoint, configuration);
    }
    final client = SystemProxyResolver.instance.createRawHttpClient(
      connectionTimeout: _onlineIdleTimeout,
    );
    WebSocket? socket;
    try {
      final connecting = WebSocket.connect(
        endpoint.toString(),
        headers: headers,
        customClient: client,
      ).timeout(_onlineIdleTimeout);
      socket = await awaitWithCancelSignal<WebSocket>(
        connecting,
        cancelSignal: cancelSignal,
      );
      if (socket == null) throw const OfflineSpeechTestCancelled();
      final activeSocket = socket;
      final format = _xfyunAudioEncoding(configuration);
      final business = <String, Object?>{
        'aue': format,
        'auf': _configurationText(configuration, 'auf'),
        'vcn': _configurationText(configuration, 'vcn'),
        'speed': _integerValue(configuration['speed']).clamp(0, 100),
        'volume': _integerValue(configuration['volume']).clamp(0, 100),
        'pitch': _integerValue(configuration['pitch']).clamp(0, 100),
        'bgs': _integerValue(configuration['bgs']),
        'tte': encoding,
        'reg': _configurationText(configuration, 'reg'),
        'rdn': _configurationText(configuration, 'rdn'),
      };
      if (format == 'lame' && _configurationBool(configuration, 'sfl')) {
        business['sfl'] = 1;
      }
      activeSocket.add(
        jsonEncode(<String, Object?>{
          'common': <String, Object?>{
            'app_id': _configurationText(configuration, 'app_id'),
          },
          'business': business,
          'data': <String, Object?>{
            'status': 2,
            'text': base64Encode(encodedText),
          },
        }),
      );
      final bytes = onAudio == null ? BytesBuilder(copy: false) : null;
      var receivedAudioBytes = 0;
      var binaryPrefixBytes = 0;

      void appendAudio(Uint8List chunk) {
        if (chunk.isEmpty) return;
        receivedAudioBytes += chunk.length;
        if (receivedAudioBytes > _maxOnlineAudioBytes) {
          throw const FormatException('讯飞语音合成结果超过安全上限。');
        }
        bytes?.add(chunk);
        onAudio?.call(chunk);
      }

      Future<void> receive() async {
        await for (final event in activeSocket.timeout(_onlineIdleTimeout)) {
          if (event is String) {
            if (event.length > _maxOnlineEventCharacters) {
              throw const FormatException('讯飞语音合成响应超过安全上限。');
            }
            final payload = jsonDecode(event);
            if (payload is! Map) continue;
            final code = _integerValue(payload['code']);
            if (code != 0) {
              throw StateError(
                '讯飞语音合成失败（$code）：${payload['message'] ?? '未知错误'}',
              );
            }
            final data = payload['data'];
            if (data is Map) {
              final cid = '${payload['cid'] ?? ''}';
              final audioStream = '${data['audio_stream'] ?? ''}';
              binaryPrefixBytes = utf8.encode(cid + audioStream).length;
              final encodedAudio = data['audio'];
              if (encodedAudio is String && encodedAudio.isNotEmpty) {
                appendAudio(Uint8List.fromList(base64Decode(encodedAudio)));
              }
              if (data['status'] == 2) break;
            }
          } else if (event is List<int>) {
            if (event.length > _maxOnlineAudioBytes) {
              throw const FormatException('讯飞语音合成二进制帧超过安全上限。');
            }
            final offset = binaryPrefixBytes.clamp(0, event.length);
            appendAudio(Uint8List.fromList(event.sublist(offset)));
          }
        }
      }

      final received = await awaitWithCancelSignal<bool>(
        receive().then((_) => true),
        cancelSignal: cancelSignal,
      ).timeout(_inferenceTimeout);
      if (received != true) throw const OfflineSpeechTestCancelled();
      return (
        bytes: bytes?.takeBytes() ?? Uint8List(0),
        sampleRate: _xfyunSampleRate(configuration),
        extension: _xfyunAudioExtension(format),
      );
    } finally {
      try {
        await socket
            ?.close(WebSocketStatus.normalClosure)
            .timeout(_realtimeCloseTimeout);
      } catch (_) {}
      client.close(force: true);
    }
  }

  Uri _xfyunTtsAuthorizedUri(Uri endpoint, Map<String, Object?> configuration) {
    final date = HttpDate.format(DateTime.now().toUtc());
    final path = endpoint.path.isEmpty ? '/v2/tts' : endpoint.path;
    final signatureOrigin =
        'host: ${endpoint.host}\ndate: $date\nGET $path HTTP/1.1';
    final signature = base64Encode(
      Hmac(
        sha256,
        utf8.encode(_configurationText(configuration, 'api_secret')),
      ).convert(utf8.encode(signatureOrigin)).bytes,
    );
    final authorization =
        'api_key="${_configurationText(configuration, 'api_key')}", '
        'algorithm="hmac-sha256", headers="host date request-line", '
        'signature="$signature"';
    return endpoint.replace(
      queryParameters: <String, String>{
        ...endpoint.queryParameters,
        'authorization': base64Encode(utf8.encode(authorization)),
        'date': date,
        'host': endpoint.host,
      },
    );
  }

  static Future<({Uint8List pcm, int sampleRate})> _readPcm16Wav(
    String path,
  ) async {
    final file = File(path);
    final length = await file.length();
    if (length <= 44 || length > _maxOnlineAudioBytes) {
      throw StateError('录音文件为空或超过 64 MB 上限。');
    }
    final bytes = await file.readAsBytes();
    if (ascii.decode(bytes.sublist(0, 4), allowInvalid: true) != 'RIFF' ||
        ascii.decode(bytes.sublist(8, 12), allowInvalid: true) != 'WAVE') {
      throw StateError('录音必须为 WAV 格式。');
    }
    final view = ByteData.sublistView(bytes);
    var offset = 12;
    var sampleRate = 0;
    var validFormat = false;
    Uint8List? pcm;
    while (offset + 8 <= bytes.length) {
      final id = ascii.decode(
        bytes.sublist(offset, offset + 4),
        allowInvalid: true,
      );
      final chunkSize = view.getUint32(offset + 4, Endian.little);
      final dataOffset = offset + 8;
      final dataEnd = dataOffset + chunkSize;
      if (dataEnd > bytes.length) throw StateError('WAV 数据块不完整。');
      if (id == 'fmt ' && chunkSize >= 16) {
        final audioFormat = view.getUint16(dataOffset, Endian.little);
        final channels = view.getUint16(dataOffset + 2, Endian.little);
        sampleRate = view.getUint32(dataOffset + 4, Endian.little);
        final bits = view.getUint16(dataOffset + 14, Endian.little);
        validFormat = audioFormat == 1 && channels == 1 && bits == 16;
      } else if (id == 'data') {
        pcm = Uint8List.fromList(bytes.sublist(dataOffset, dataEnd));
      }
      offset = dataEnd + (chunkSize.isOdd ? 1 : 0);
    }
    if (!validFormat || pcm == null || pcm.isEmpty) {
      throw StateError('录音必须为单声道 16-bit PCM WAV。');
    }
    return (pcm: pcm, sampleRate: sampleRate);
  }

  static Uint8List _downsamplePcm16(
    Uint8List source, {
    required int from,
    required int to,
  }) {
    if (from == to) return source;
    if (from != 16000 || to != 8000) {
      throw StateError('仅支持将 16 kHz PCM 转换为 8 kHz。');
    }
    final output = Uint8List((source.length ~/ 4) * 2);
    for (
      var input = 0, target = 0;
      input + 1 < source.length && target + 1 < output.length;
      input += 4, target += 2
    ) {
      output[target] = source[input];
      output[target + 1] = source[input + 1];
    }
    return output;
  }

  static String _sortedQuery(Map<String, String> parameters) {
    final keys = parameters.keys.toList()..sort();
    return keys
        .map(
          (key) =>
              '${Uri.encodeQueryComponent(key)}='
              '${Uri.encodeQueryComponent(parameters[key]!)}',
        )
        .join('&');
  }

  static void _addNonEmptyParameter(
    Map<String, String> target,
    String targetKey,
    Map<String, Object?> source,
    String sourceKey,
  ) {
    final value = _configurationText(source, sourceKey);
    if (value.isNotEmpty) target[targetKey] = value;
  }

  static String _configurationText(
    Map<String, Object?> configuration,
    String key,
  ) => '${configuration[key] ?? ''}'.trim();

  static bool _configurationBool(
    Map<String, Object?> configuration,
    String key,
  ) => configuration[key] == true;

  static int _integerValue(Object? value) =>
      value is num ? value.round() : int.tryParse('$value') ?? 0;

  static int _xfyunSampleRate(Map<String, Object?> configuration) =>
      _configurationText(configuration, 'auf').contains('8000') ? 8000 : 16000;

  static String _xfyunAudioEncoding(Map<String, Object?> configuration) {
    final format = _configurationText(configuration, 'aue');
    if (!format.startsWith('speex')) return format;
    final level = _integerValue(
      configuration['compression_level'],
    ).clamp(1, 10);
    return '$format;$level';
  }

  static String _xfyunAudioExtension(String format) {
    if (format == 'raw') return '.pcm';
    if (format == 'lame') return '.mp3';
    if (format.startsWith('opus')) return '.opus';
    return '.spx';
  }

  static String _xfyunCharsetName(String encoding) => switch (encoding) {
    'GB2312' => 'gb2312',
    'GBK' => 'gbk',
    'BIG5' => 'big5',
    'UNICODE' => 'utf-16-le',
    'GB18030' => 'gb18030',
    _ => 'utf-8',
  };

  Future<void> shutdown() => _shutdownOnce.run(_shutdown);

  Future<void> _shutdown() async {
    _shuttingDown = true;
    if (!_shutdownSignal.isCompleted) _shutdownSignal.complete();

    final downloads = _downloadCancellations.values.toList(growable: false);
    for (final cancellation in downloads) {
      cancellation.cancel();
    }

    final sessions = _processes.values.toSet().toList(growable: false);
    _processes.clear();
    final audioStreams = _activeAudioStreams.keys.toList(growable: false);
    _activeAudioStreams.clear();
    for (final stream in audioStreams) {
      await stream.close();
    }
    for (final session in sessions) {
      session.failPending(StateError('应用正在退出。'));
    }

    final cleanupTasks = <Future<void>>[
      for (final session in sessions)
        terminateTrackedProcessTree(session.process),
      for (final cancellation in downloads) cancellation.done,
      for (final operation in _activeStarts)
        operation.then<void>((_) {}, onError: (_, _) {}),
      for (final operation in _activeTests)
        operation.then<void>((_) {}, onError: (_, _) {}),
    ];
    if (cleanupTasks.isNotEmpty) {
      await Future.wait<void>(cleanupTasks).timeout(runtimeCleanupTimeout);
    }
    _runtimePreparations.clear();
  }

  void _throwIfShuttingDown() {
    if (_shuttingDown) throw StateError('应用正在退出，无法启动新的语音任务。');
  }

  static Future<void> _deleteTemporaryDirectory(Directory? directory) async {
    if (directory == null) return;
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
    } catch (_) {}
  }

  static Uint8List _pcm16Wav(Uint8List pcm, int sampleRate, int channels) {
    final output = Uint8List(44 + pcm.length);
    final header = ByteData.sublistView(output);
    void ascii(int offset, String value) {
      for (var index = 0; index < value.length; index += 1) {
        output[offset + index] = value.codeUnitAt(index);
      }
    }

    ascii(0, 'RIFF');
    header.setUint32(4, 36 + pcm.length, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, sampleRate * channels * 2, Endian.little);
    header.setUint16(32, channels * 2, Endian.little);
    header.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    header.setUint32(40, pcm.length, Endian.little);
    output.setRange(44, output.length, pcm);
    return output;
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
    if (_shuttingDown) return;
    if (kIsWeb || Platform.isAndroid || Platform.isIOS) {
      _hardwareProfile = OfflineSpeechHardwareProfile(
        platformSupported: false,
        architecture: 'unsupported',
        logicalCores: kIsWeb ? 0 : Platform.numberOfProcessors,
        totalMemoryBytes: 0,
        freeStorageBytes: 0,
      );
      if (!_shuttingDown) notifyListeners();
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
    if (!_shuttingDown) notifyListeners();
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
    if (!_shuttingDown) notifyListeners();
  }
}

class _DownloadCancellation {
  bool cancelled = false;
  HttpClient? client;
  final Completer<void> _cancelCompleter = Completer<void>();
  final Completer<void> _finishedCompleter = Completer<void>();

  Future<void> get cancelSignal => _cancelCompleter.future;
  Future<void> get done => _finishedCompleter.future;

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

  void finish() {
    if (!_finishedCompleter.isCompleted) _finishedCompleter.complete();
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
  static const String _realtimePrefix = 'OPENHAND_实时通道 ';

  final Process process;
  final Completer<void> ready = Completer<void>();
  final Map<String, Completer<Map<String, Object?>>> _pending =
      <String, Completer<Map<String, Object?>>>{};
  final Map<String, void Function()> _discardedResponseHandlers =
      <String, void Function()>{};
  int _requestSequence = 0;
  String errors = '';
  Uri? realtimeEndpoint;

  Future<Map<String, Object?>> request(
    Map<String, Object?> request, {
    required Duration timeout,
    Future<void>? cancelSignal,
    void Function()? onDiscardedResponse,
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
      final response = await awaitWithCancelSignal<Map<String, Object?>>(
        completer.future,
        cancelSignal: cancelSignal,
      ).timeout(timeout);
      if (response == null) {
        _discardResponse(id, completer, onDiscardedResponse);
        throw const OfflineSpeechTestCancelled();
      }
      return response;
    } on TimeoutException {
      _discardResponse(id, completer, onDiscardedResponse);
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
    for (final handler in _discardedResponseHandlers.values) {
      handler();
    }
    _discardedResponseHandlers.clear();
  }

  void _handleOutput(String line) {
    if (line.startsWith(_realtimePrefix)) {
      try {
        final endpoint = Uri.parse(
          utf8.decode(base64Url.decode(line.substring(_realtimePrefix.length))),
        );
        if (endpoint.scheme != 'ws' ||
            endpoint.host != InternetAddress.loopbackIPv4.address ||
            endpoint.port <= 0 ||
            (endpoint.queryParameters['token'] ?? '').length < 32) {
          throw const FormatException('实时语音通道地址无效。');
        }
        realtimeEndpoint = endpoint;
      } catch (error, stack) {
        if (!ready.isCompleted) {
          ready.completeError(StateError('无法解析模型实时语音通道：$error'), stack);
        }
      }
      return;
    }
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
      final discardedHandler = _discardedResponseHandlers.remove(id);
      if (discardedHandler != null) {
        discardedHandler();
        return;
      }
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

  void _discardResponse(
    String id,
    Completer<Map<String, Object?>> completer,
    void Function()? handler,
  ) {
    _pending.remove(id);
    if (handler == null) return;
    if (completer.isCompleted) {
      handler();
    } else {
      _discardedResponseHandlers[id] = handler;
    }
  }
}

const String _runtimeHostSource = r'''
import argparse, array, asyncio, base64, json, os, secrets, sys, threading, traceback, urllib.parse, wave

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

def pcm16_bytes(samples, volume=1.0):
    values = flatten_samples(samples)
    if not values: return b""
    pcm = array.array("h", (
        int(max(-1.0, min(1.0, value * volume)) * 32767) for value in values
    ))
    if sys.byteorder == "big": pcm.byteswap()
    return pcm.tobytes()

def collect_speech(generated):
    samples = []
    for chunk in generated:
        if isinstance(chunk, dict) and "tts_speech" in chunk:
            samples.extend(flatten_samples(chunk["tts_speech"]))
    return samples

def cosyvoice_stream(loaded, text, config):
    reference_audio = str(config.get("reference_audio", "")).strip()
    if not reference_audio:
        reference_audio = os.path.join(os.getcwd(), "source", "asset", "zero_shot_prompt.wav")
    if not os.path.isfile(reference_audio):
        raise RuntimeError("请先选择有效的参考音频")
    speed = float(config.get("speed", 1.0))
    text_frontend = bool(config.get("text_frontend", True))
    instruct = str(config.get("instruct", "")).strip()
    generated_any = False
    if hasattr(loaded, "inference_instruct2") and instruct:
        prompt = "You are a helpful assistant. " + instruct + "<|endofprompt|>"
        generated = loaded.inference_instruct2(
            text, prompt, reference_audio, stream=True,
            speed=speed, text_frontend=text_frontend,
        )
        try:
            for chunk in generated:
                if not isinstance(chunk, dict) or "tts_speech" not in chunk: continue
                audio = pcm16_bytes(chunk["tts_speech"], float(config.get("volume", 1.0)))
                if audio:
                    generated_any = True
                    yield audio
        finally:
            close = getattr(generated, "close", None)
            if close: close()
    if generated_any: return
    prompt_text = str(config.get("prompt_text", "")).strip()
    if not prompt_text:
        prompt_text = "You are a helpful assistant.<|endofprompt|>希望你以后能够做的比我还好呦。"
    generated = loaded.inference_zero_shot(
        text, prompt_text, reference_audio, stream=True,
        speed=speed, text_frontend=text_frontend,
    )
    try:
        for chunk in generated:
            if not isinstance(chunk, dict) or "tts_speech" not in chunk: continue
            audio = pcm16_bytes(chunk["tts_speech"], float(config.get("volume", 1.0)))
            if audio: yield audio
    finally:
        close = getattr(generated, "close", None)
        if close: close()

def start_realtime_server(loaded, config, model_lock):
    import websockets
    token = secrets.token_urlsafe(32)
    ready = threading.Event()
    state = {}
    async def handle(websocket):
        query = urllib.parse.parse_qs(urllib.parse.urlsplit(websocket.path).query)
        supplied = query.get("token", [""])[0]
        if not secrets.compare_digest(supplied, token):
            await websocket.close(1008, "拒绝访问")
            return
        try:
            raw = await asyncio.wait_for(websocket.recv(), timeout=10)
            request = json.loads(raw)
            if request.get("operation") != "synthesize_stream":
                raise RuntimeError("不支持的实时语音操作")
            await websocket.send(json.dumps({
                "type": "start", "sample_rate": int(loaded.sample_rate),
                "channels": 1, "format": "pcm_s16le",
            }, ensure_ascii=False))
            while True:
                raw = await asyncio.wait_for(websocket.recv(), timeout=300)
                message = json.loads(raw)
                message_type = message.get("type")
                if message_type == "finish":
                    await websocket.send(json.dumps({"type": "end"}))
                    return
                if message_type != "text":
                    raise RuntimeError("不支持的实时语音消息")
                text = str(message.get("text", "")).strip()
                if not any(character.isalnum() for character in text): continue
                chunks = 0
                await asyncio.to_thread(model_lock.acquire)
                try:
                    for audio in cosyvoice_stream(loaded, text, config):
                        await websocket.send(audio)
                        chunks += 1
                finally:
                    model_lock.release()
                if chunks == 0: raise RuntimeError("模型没有生成音频采样")
        except websockets.exceptions.ConnectionClosed:
            pass
        except Exception as error:
            try:
                await websocket.send(json.dumps({
                    "type": "error", "message": str(error),
                }, ensure_ascii=False))
            except Exception:
                pass

    async def serve():
        async with websockets.serve(
            handle, "127.0.0.1", 0, compression=None,
            max_size=1024 * 1024, max_queue=4, ping_interval=None,
        ) as server:
            port = server.sockets[0].getsockname()[1]
            state["endpoint"] = "ws://127.0.0.1:{}/speech?token={}".format(port, token)
            ready.set()
            await asyncio.Future()

    def run():
        try:
            asyncio.run(serve())
        except Exception as error:
            state["error"] = str(error)
            ready.set()

    threading.Thread(target=run, name="openhand-tts-ws", daemon=True).start()
    if not ready.wait(10): raise RuntimeError("实时语音通道启动超时")
    if state.get("error"): raise RuntimeError("实时语音通道启动失败：" + state["error"])
    return state["endpoint"]

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
    text = str(text or "").strip()
    if not any(character.isalnum() for character in text):
        raise RuntimeError("文本没有可朗读内容")
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
        if len(wavs) == 0: raise RuntimeError("模型没有生成音频采样")
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
            samples = collect_speech(generated)
        else:
            samples = []
        if not samples:
            prompt_text = str(config.get("prompt_text", "")).strip()
            if not prompt_text:
                prompt_text = "You are a helpful assistant.<|endofprompt|>希望你以后能够做的比我还好呦。"
            generated = loaded.inference_zero_shot(
                text, prompt_text, reference_audio, stream=False,
                speed=speed, text_frontend=text_frontend,
            )
            samples = collect_speech(generated)
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

def handle_request(runtime, loaded, config, request, model_lock):
    with model_lock:
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
    model_lock = threading.Lock()
    if args.runtime == "cosyVoice":
        endpoint = start_realtime_server(loaded, config, model_lock)
        encoded = base64.urlsafe_b64encode(endpoint.encode("utf-8")).decode("ascii")
        print("OPENHAND_实时通道 " + encoded, flush=True)
    print("OPENHAND_模型就绪", flush=True)
    for line in sys.stdin:
        line = line.strip()
        if not line: continue
        request_id = ""
        try:
            request = json.loads(base64.urlsafe_b64decode(line).decode("utf-8"))
            request_id = str(request.get("id", ""))
            respond(request_id, result=handle_request(args.runtime, loaded, config, request, model_lock))
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

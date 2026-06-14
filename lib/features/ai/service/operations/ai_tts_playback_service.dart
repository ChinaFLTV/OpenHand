import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../../../app/support/openhand_paths.dart';
import '../../../../app/support/safe_subprocess.dart';
import '../../../../app/support/silent_log.dart';
import '../../model/ai_tts_settings.dart';

class AiTtsPlaybackSnapshot {
  const AiTtsPlaybackSnapshot({
    this.playing = false,
    this.messageId,
    this.provider,
  });

  final bool playing;
  final String? messageId;
  final AiTtsProvider? provider;
}

class AiTtsPlaybackService {
  AiTtsPlaybackService();

  final ValueNotifier<AiTtsPlaybackSnapshot> state =
      ValueNotifier<AiTtsPlaybackSnapshot>(const AiTtsPlaybackSnapshot());
  int _generation = 0;
  Process? _activeProcess;
  WebSocket? _activeWebSocket;
  http.Client? _activeClient;

  bool isPlayingMessage(String messageId) {
    final snapshot = state.value;
    return snapshot.playing && snapshot.messageId == messageId;
  }

  Future<void> toggleMessage({
    required String messageId,
    required String text,
    required AiTtsSettings settings,
  }) async {
    if (isPlayingMessage(messageId)) {
      await stop();
      return;
    }
    await speak(messageId: messageId, text: text, settings: settings);
  }

  Future<void> speak({
    required String messageId,
    required String text,
    required AiTtsSettings settings,
  }) async {
    await stop();
    final normalized = settings.normalized();
    if (!normalized.enabled) return;
    final content = _normalizeText(text, normalized.maxTextCharacters);
    if (content.isEmpty) return;
    final generation = ++_generation;
    for (final provider in normalized.providerPriority) {
      if (generation != _generation) return;
      final providerSettings = normalized.provider(provider);
      if (!providerSettings.enabled) continue;
      state.value = AiTtsPlaybackSnapshot(
        playing: true,
        messageId: messageId,
        provider: provider,
      );
      try {
        await _speakWithProvider(
          providerSettings,
          content,
          timeout: Duration(seconds: normalized.timeoutSeconds),
        );
        if (generation == _generation) await stop();
        return;
      } catch (error, stack) {
        silentLog('tts', 'provider ${provider.storageKey}', error, stack);
        await _stopActiveResources(clearState: false);
      }
    }
    if (generation == _generation) {
      state.value = const AiTtsPlaybackSnapshot();
    }
  }

  Future<void> stop() async {
    _generation += 1;
    await _stopActiveResources(clearState: true);
  }

  Future<void> dispose() async {
    await stop();
    state.dispose();
  }

  Future<void> _speakWithProvider(
    AiTtsProviderSettings provider,
    String text, {
    required Duration timeout,
  }) {
    switch (provider.provider) {
      case AiTtsProvider.system:
      case AiTtsProvider.apple:
        return _speakWithSystem(provider, text, timeout: timeout);
      case AiTtsProvider.xfyun:
        return _speakWithXfyun(provider, text, timeout: timeout);
      case AiTtsProvider.baidu:
        return _speakWithBaidu(provider, text, timeout: timeout);
      case AiTtsProvider.youdao:
      case AiTtsProvider.bing:
      case AiTtsProvider.google:
        return Future<void>.error(
          UnsupportedError(
            '${provider.provider.storageKey} TTS requires configured audio playback integration.',
          ),
        );
    }
  }

  Future<void> _speakWithSystem(
    AiTtsProviderSettings settings,
    String text, {
    required Duration timeout,
  }) async {
    if (Platform.isMacOS) {
      final args = <String>[];
      if (settings.voice.isNotEmpty) {
        args.addAll(<String>['-v', settings.voice]);
      }
      args.addAll(<String>['-r', '${_systemRate(settings.speed)}', text]);
      await _runSpeechProcess('say', args, timeout: timeout);
      return;
    }
    if (Platform.isWindows) {
      final script = _windowsSpeechScript(text, settings);
      await _runSpeechProcess('powershell', <String>[
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        script,
      ], timeout: timeout);
      return;
    }
    if (Platform.isLinux) {
      await _runSpeechProcess('spd-say', <String>[
        '-r',
        '${_linuxRate(settings.speed)}',
        text,
      ], timeout: timeout);
      return;
    }
    throw UnsupportedError('System TTS is not available on this platform.');
  }

  Future<void> _speakWithXfyun(
    AiTtsProviderSettings settings,
    String text, {
    required Duration timeout,
  }) async {
    if (settings.appId.isEmpty ||
        settings.apiKey.isEmpty ||
        settings.apiSecret.isEmpty) {
      throw StateError('Xfyun TTS credentials are incomplete.');
    }
    final endpoint = settings.endpoint.isEmpty
        ? AiTtsProviderSettings.defaults(AiTtsProvider.xfyun).endpoint
        : settings.endpoint;
    final uri = _xfyunAuthorizedUri(Uri.parse(endpoint), settings);
    final ws = await WebSocket.connect('$uri').timeout(timeout);
    _activeWebSocket = ws;
    final audioBytes = BytesBuilder(copy: false);
    ws.add(
      jsonEncode(<String, Object?>{
        'common': <String, Object?>{'app_id': settings.appId},
        'business': <String, Object?>{
          'aue': '${settings.extra['aue'] ?? 'lame'}',
          'auf': '${settings.extra['auf'] ?? 'audio/L16;rate=16000'}',
          'vcn': settings.voice.isEmpty ? 'xiaoyan' : settings.voice,
          'speed': settings.speed.round().clamp(0, 100),
          'volume': settings.volume.round().clamp(0, 100),
          'pitch': settings.pitch.round().clamp(0, 100),
          'tte': 'UTF8',
        },
        'data': <String, Object?>{
          'status': 2,
          'text': base64Encode(utf8.encode(text)),
        },
      }),
    );
    await for (final event in ws.timeout(timeout)) {
      if (event is! String) continue;
      final decoded = jsonDecode(event);
      if (decoded is! Map) continue;
      final code = decoded['code'];
      if (code is int && code != 0) {
        throw StateError('Xfyun TTS failed: ${decoded['message'] ?? code}');
      }
      final data = decoded['data'];
      if (data is Map) {
        final audio = data['audio'];
        if (audio is String && audio.isNotEmpty) {
          audioBytes.add(base64Decode(audio));
        }
        if (data['status'] == 2) break;
      }
    }
    try {
      await ws.close().timeout(const Duration(seconds: 1));
    } finally {
      if (identical(_activeWebSocket, ws)) _activeWebSocket = null;
    }
    await _playAudioBytes(
      audioBytes.takeBytes(),
      extension: '${settings.extra['aue'] ?? 'mp3'}' == 'raw' ? '.pcm' : '.mp3',
      timeout: timeout,
    );
  }

  Future<void> _speakWithBaidu(
    AiTtsProviderSettings settings,
    String text, {
    required Duration timeout,
  }) async {
    if (settings.accessToken.isEmpty) {
      throw StateError('Baidu TTS access_token is empty.');
    }
    final endpoint = settings.endpoint.isEmpty
        ? AiTtsProviderSettings.defaults(AiTtsProvider.baidu).endpoint
        : settings.endpoint;
    final uri = Uri.parse(endpoint).replace(
      queryParameters: <String, String>{
        'tex': text,
        'tok': settings.accessToken,
        'cuid': 'openhand',
        'ctp': '1',
        'lan': settings.language.isEmpty ? 'zh' : settings.language,
        'spd': '${settings.speed.round().clamp(0, 15)}',
        'pit': '${settings.pitch.round().clamp(0, 15)}',
        'vol': '${settings.volume.round().clamp(0, 15)}',
        'per': settings.voice.isEmpty ? '0' : settings.voice,
        'aue': '3',
      },
    );
    final client = http.Client();
    _activeClient = client;
    try {
      final response = await client.get(uri).timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('Baidu TTS HTTP ${response.statusCode}', uri: uri);
      }
      final contentType = response.headers['content-type'] ?? '';
      if (!contentType.startsWith('audio/')) {
        throw StateError('Baidu TTS returned non-audio response.');
      }
      await _playAudioBytes(
        response.bodyBytes,
        extension: '.mp3',
        timeout: timeout,
      );
    } finally {
      if (identical(_activeClient, client)) _activeClient = null;
      client.close();
    }
  }

  Future<void> _playAudioBytes(
    List<int> bytes, {
    required String extension,
    required Duration timeout,
  }) async {
    if (bytes.isEmpty) throw StateError('TTS returned empty audio.');
    if (!Platform.isMacOS) {
      throw UnsupportedError('Audio playback is only wired for macOS now.');
    }
    final dir = Directory(
      p.join(OpenHandPaths.defaultCacheDirectoryPath(), 'tts'),
    );
    await dir.create(recursive: true);
    final file = File(
      p.join(
        dir.path,
        'tts_${DateTime.now().microsecondsSinceEpoch}$extension',
      ),
    );
    await file.writeAsBytes(bytes, flush: true);
    try {
      await _runSpeechProcess('afplay', <String>[file.path], timeout: timeout);
    } finally {
      unawaited(file.delete().catchError((_) => file));
    }
  }

  Future<void> _runSpeechProcess(
    String executable,
    List<String> args, {
    required Duration timeout,
  }) async {
    final process = await startTrackedProcess(executable, args);
    _activeProcess = process;
    try {
      final exitCode = await process.exitCode.timeout(timeout);
      if (exitCode != 0) {
        throw ProcessException(executable, args, 'exit $exitCode', exitCode);
      }
    } on TimeoutException {
      process.kill();
      throw TimeoutException('TTS process timed out.', timeout);
    } finally {
      if (identical(_activeProcess, process)) _activeProcess = null;
    }
  }

  Future<void> _stopActiveResources({required bool clearState}) async {
    final process = _activeProcess;
    _activeProcess = null;
    if (process != null) {
      try {
        process.kill();
      } catch (_) {}
    }
    final ws = _activeWebSocket;
    _activeWebSocket = null;
    if (ws != null) {
      try {
        await ws.close().timeout(const Duration(seconds: 1));
      } catch (_) {}
    }
    final client = _activeClient;
    _activeClient = null;
    client?.close();
    if (clearState) {
      state.value = const AiTtsPlaybackSnapshot();
    }
  }

  Uri _xfyunAuthorizedUri(Uri endpoint, AiTtsProviderSettings settings) {
    final date = HttpDate.format(DateTime.now().toUtc());
    final host = endpoint.host;
    final path = endpoint.path.isEmpty ? '/v2/tts' : endpoint.path;
    final signatureOrigin = 'host: $host\ndate: $date\nGET $path HTTP/1.1';
    final signatureSha = Hmac(
      sha256,
      utf8.encode(settings.apiSecret),
    ).convert(utf8.encode(signatureOrigin));
    final authorizationOrigin =
        'api_key="${settings.apiKey}", algorithm="hmac-sha256", headers="host date request-line", signature="${base64Encode(signatureSha.bytes)}"';
    return endpoint.replace(
      queryParameters: <String, String>{
        ...endpoint.queryParameters,
        'authorization': base64Encode(utf8.encode(authorizationOrigin)),
        'date': date,
        'host': host,
      },
    );
  }

  static String _normalizeText(String text, int maxCharacters) {
    final trimmed = text
        .replaceAll(RegExp(r'```[\s\S]*?```'), ' ')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (trimmed.length <= maxCharacters) return trimmed;
    return trimmed.substring(0, maxCharacters);
  }

  static int _systemRate(double speed) {
    if (speed > 10) return speed.round().clamp(80, 420);
    return (175 * speed.clamp(0.5, 2.0)).round();
  }

  static int _linuxRate(double speed) {
    if (speed > 10) return ((speed - 50) * 2).round().clamp(-100, 100);
    return ((speed - 1.0) * 100).round().clamp(-100, 100);
  }

  static String _windowsSpeechScript(
    String text,
    AiTtsProviderSettings settings,
  ) {
    final escaped = text.replaceAll("'", "''");
    final volume =
        (settings.volume <= 1 ? settings.volume * 100 : settings.volume)
            .round()
            .clamp(0, 100);
    final rate = settings.speed > 10
        ? ((settings.speed - 50) / 5).round().clamp(-10, 10)
        : ((settings.speed - 1) * 5).round().clamp(-10, 10);
    return "Add-Type -AssemblyName System.Speech; "
        "\$s = New-Object System.Speech.Synthesis.SpeechSynthesizer; "
        "\$s.Volume = $volume; \$s.Rate = $rate; "
        "\$s.Speak('$escaped'); \$s.Dispose();";
  }
}

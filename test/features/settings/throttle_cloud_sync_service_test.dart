import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:openhand/features/settings/service/throttle_cloud_sync_service.dart';

void main() {
  test('legacy or unknown providers fall back to custom HTTP', () {
    expect(
      ThrottleCloudSyncProvider.fromStorage('oauth'),
      ThrottleCloudSyncProvider.custom,
    );
    expect(
      ThrottleCloudSyncProvider.fromStorage('unknown'),
      ThrottleCloudSyncProvider.custom,
    );
  });

  test('supported provider storage values round trip', () {
    for (final provider in ThrottleCloudSyncProvider.values) {
      expect(
        ThrottleCloudSyncProvider.fromStorage(provider.storageValue),
        provider,
      );
    }
  });

  test(
    'injected client remains caller-owned and disposed service rejects work',
    () async {
      final client = _TrackingClient(
        (_) async => _jsonResponse(<String, Object?>{
          'config': <String, Object?>{'throttle_enabled': true},
          'updated_at_ms': 42,
        }),
      );
      final service = ThrottleCloudSyncService(
        client: client,
        registerCloudChangeHandler: false,
      );

      final pulled = await service.pull(
        provider: ThrottleCloudSyncProvider.custom,
        endpoint: 'https://sync.example/config',
        token: '',
      );
      expect(pulled.ok, isTrue);
      expect(pulled.updatedAtMs, 42);

      await service.dispose();
      final afterDispose = await service.pull(
        provider: ThrottleCloudSyncProvider.custom,
        endpoint: 'https://sync.example/config',
        token: '',
      );
      expect(afterDispose.ok, isFalse);
      expect(client.sendCount, 1);
      expect(client.closeCount, 0);

      client.close();
      expect(client.closeCount, 1);
    },
  );

  test('dispose closes an owned client with an in-flight request', () async {
    late _HangingClient activeClient;
    final service = ThrottleCloudSyncService(
      clientFactory: () => activeClient = _HangingClient(),
      registerCloudChangeHandler: false,
    );

    final pull = service.pull(
      provider: ThrottleCloudSyncProvider.custom,
      endpoint: 'https://sync.example/config',
      token: '',
    );
    await activeClient.sendStarted.future;
    await service.dispose();
    final result = await pull;

    expect(result.ok, isFalse);
    expect(activeClient.closeCount, 1);
  });

  test(
    'custom HTTP response is rejected at the configured byte limit',
    () async {
      final oversized = List<int>.filled(2 * 1024 * 1024 + 1, 65);
      final client = _TrackingClient(
        (_) async =>
            http.StreamedResponse(Stream<List<int>>.value(oversized), 200),
      );
      final service = ThrottleCloudSyncService(
        client: client,
        registerCloudChangeHandler: false,
      );

      final result = await service.pull(
        provider: ThrottleCloudSyncProvider.custom,
        endpoint: 'https://sync.example/config',
        token: '',
      );

      expect(result.ok, isFalse);
      expect(result.message, contains('byte limit'));
      await service.dispose();
      client.close();
    },
  );
}

http.StreamedResponse _jsonResponse(Map<String, Object?> body) {
  final bytes = utf8.encode(jsonEncode(body));
  return http.StreamedResponse(
    Stream<List<int>>.value(bytes),
    200,
    contentLength: bytes.length,
    headers: <String, String>{'content-type': 'application/json'},
  );
}

class _TrackingClient extends http.BaseClient {
  _TrackingClient(this._handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request)
  _handler;
  int sendCount = 0;
  int closeCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    sendCount += 1;
    return _handler(request);
  }

  @override
  void close() {
    closeCount += 1;
  }
}

class _HangingClient extends http.BaseClient {
  final Completer<void> sendStarted = Completer<void>();
  final Completer<http.StreamedResponse> _response =
      Completer<http.StreamedResponse>();
  int closeCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (!sendStarted.isCompleted) sendStarted.complete();
    return _response.future;
  }

  @override
  void close() {
    closeCount += 1;
    if (!_response.isCompleted) {
      _response.complete(
        http.StreamedResponse(const Stream<List<int>>.empty(), 499),
      );
    }
  }
}

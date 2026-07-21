import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/model/ai_usage_analytics.dart';
import 'package:openhand/features/ai/service/runtime/ai_transport_client.dart';
import 'package:openhand/features/ai/service/usage/ai_usage_tracker.dart';
import 'package:openhand/shared/db/database_service.dart';

void main() {
  late Directory temporaryDirectory;
  final tracker = AiUsageTracker.instance;

  setUpAll(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'openhand-ai-usage-test-',
    );
    await DatabaseService.initialize(
      databasePath: '${temporaryDirectory.path}/openhand.db',
      useNoIsolateFactory: true,
    );
  });

  setUp(() => tracker.clear());

  tearDownAll(() async {
    await DatabaseService.instance.close();
    await temporaryDirectory.delete(recursive: true);
  });

  test('请求超时会记录阶段、阈值并脱敏错误信息', () async {
    final startedAt = DateTime.utc(2026, 7, 21, 10);
    tracker.recordFailure(
      model: _model,
      apiFamily: 'chat_completions',
      startedAt: startedAt,
      endedAt: startedAt.add(const Duration(seconds: 12)),
      error: TimeoutException(
        'HTTP response headers exceeded the request time limit. '
        'Authorization: Bearer secret-token',
        const Duration(seconds: 12),
      ),
    );

    final record = await _singleRecord(tracker);
    expect(record.status, AiUsageRequestStatus.timeout);
    expect(record.timeoutMs, 12000);
    expect(record.timeoutPhase, 'response_headers');
    expect(record.errorType, 'TimeoutException');
    expect(record.errorMessage, contains('[已脱敏]'));
    expect(record.errorMessage, isNot(contains('secret-token')));
  });

  test('HTTP 请求失败会记录状态码与错误正文', () async {
    final startedAt = DateTime.utc(2026, 7, 21, 11);
    tracker.recordFailure(
      model: _model,
      apiFamily: 'responses',
      startedAt: startedAt,
      endedAt: startedAt.add(const Duration(milliseconds: 450)),
      error: AiTransportResponseException(
        statusCode: 503,
        body: '服务暂时不可用',
        uri: Uri.parse('https://example.com/v1/responses'),
      ),
    );

    final record = await _singleRecord(tracker);
    expect(record.status, AiUsageRequestStatus.failed);
    expect(record.httpStatusCode, 503);
    expect(record.errorMessage, contains('服务暂时不可用'));
  });

  test('解析异常与取消请求会分别记录', () async {
    final startedAt = DateTime.utc(2026, 7, 21, 12);
    tracker.recordFailure(
      model: _model,
      apiFamily: 'messages',
      startedAt: startedAt,
      endedAt: startedAt.add(const Duration(milliseconds: 50)),
      error: const FormatException('响应 JSON 无效'),
    );
    tracker.recordFailure(
      model: _model,
      apiFamily: 'messages',
      startedAt: startedAt,
      endedAt: startedAt.add(const Duration(milliseconds: 60)),
      error: StateError('用户已取消'),
      cancelled: true,
    );

    await tracker.flush();
    final snapshot = await tracker.loadSnapshot(
      const AiUsageFilter(range: AiUsageRange.all),
    );
    expect(snapshot.summary.errorCount, 1);
    expect(snapshot.summary.cancelledCount, 1);
    expect(snapshot.summary.failureCount, 2);
    expect(
      snapshot.recentRequests.map((record) => record.status),
      containsAll(<String>[
        AiUsageRequestStatus.error,
        AiUsageRequestStatus.cancelled,
      ]),
    );
  });

  test('网络异常与供应商业务失败会分别归类', () async {
    final startedAt = DateTime.utc(2026, 7, 21, 13);
    tracker.recordFailure(
      model: _model,
      apiFamily: 'messages',
      startedAt: startedAt,
      endedAt: startedAt.add(const Duration(milliseconds: 80)),
      error: StateError('网络连接失败'),
    );
    tracker.recordFailure(
      model: _model,
      apiFamily: 'messages',
      startedAt: startedAt,
      endedAt: startedAt.add(const Duration(milliseconds: 90)),
      error: StateError('Provider request failed: quota rejected'),
    );

    await tracker.flush();
    final snapshot = await tracker.loadSnapshot(
      const AiUsageFilter(range: AiUsageRange.all),
    );
    expect(snapshot.summary.errorCount, 1);
    expect(snapshot.summary.failedCount, 1);
  });
}

Future<AiUsageRequestRecord> _singleRecord(AiUsageTracker tracker) async {
  await tracker.flush();
  final snapshot = await tracker.loadSnapshot(
    const AiUsageFilter(range: AiUsageRange.all),
  );
  expect(snapshot.recentRequests, hasLength(1));
  return snapshot.recentRequests.single;
}

const AiModelConfig _model = AiModelConfig(
  id: 'test-provider',
  name: '测试供应商',
  baseUrl: 'https://example.com/v1',
  authScheme: AiAuthScheme.bearer,
  token: 'test-token',
  modelId: 'test-model',
  protocolType: AiProtocolType.openai,
);

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/services/model/ai_exposure_models.dart';

void main() {
  final reportedAt = DateTime.utc(2026, 8, 7, 12, 34, 56);

  test('parses reported timestamps with their provenance', () {
    final progress = AiExposureProgress.fromJson(<String, Object?>{
      'updatedAt': reportedAt.toIso8601String(),
    });
    final history = AiExposureHistoryEntry.fromJson(<String, Object?>{
      'createdAt': reportedAt.toIso8601String(),
    });
    final result = AiExposureResult.fromJson(<String, Object?>{
      'createdAt': reportedAt.toIso8601String(),
    });
    final log = AiExposureLogEntry.fromJson(<String, Object?>{
      'at': reportedAt.toIso8601String(),
    });
    final probe = AiExposureProxyProbeSample.fromJson(<String, Object?>{
      'checkedAt': reportedAt.toIso8601String(),
    });
    final request = AiExposureProxyRequestSample.fromJson(<String, Object?>{
      'atMs': reportedAt.millisecondsSinceEpoch,
    });
    final identity = AiExposureProxyIdentity.fromJson(<String, Object?>{
      'observedAt': reportedAt.toIso8601String(),
    });

    expect(progress.updatedAt, reportedAt);
    expect(progress.updatedAtReported, isTrue);
    expect(history.createdAt, reportedAt);
    expect(history.createdAtReported, isTrue);
    expect(result.createdAt, reportedAt);
    expect(result.createdAtReported, isTrue);
    expect(log.at, reportedAt);
    expect(log.atReported, isTrue);
    expect(probe.checkedAt, reportedAt);
    expect(probe.checkedAtReported, isTrue);
    expect(request.at, reportedAt.toLocal());
    expect(request.atReported, isTrue);
    expect(identity.observedAt, reportedAt);
    expect(identity.observedAtReported, isTrue);
  });

  test('marks absent timestamps as locally generated', () {
    final before = DateTime.now();
    final progress = AiExposureProgress.fromJson(<String, Object?>{});
    final history = AiExposureHistoryEntry.fromJson(<String, Object?>{});
    final result = AiExposureResult.fromJson(<String, Object?>{});
    final log = AiExposureLogEntry.fromJson(<String, Object?>{});
    final probe = AiExposureProxyProbeSample.fromJson(<String, Object?>{});
    final request = AiExposureProxyRequestSample.fromJson(<String, Object?>{});
    final identity = AiExposureProxyIdentity.fromJson(<String, Object?>{});
    final after = DateTime.now();

    _expectLocalFallback(
      timestamp: progress.updatedAt,
      reported: progress.updatedAtReported,
      before: before,
      after: after,
    );
    _expectLocalFallback(
      timestamp: history.createdAt,
      reported: history.createdAtReported,
      before: before,
      after: after,
    );
    _expectLocalFallback(
      timestamp: result.createdAt,
      reported: result.createdAtReported,
      before: before,
      after: after,
    );
    _expectLocalFallback(
      timestamp: log.at,
      reported: log.atReported,
      before: before,
      after: after,
    );
    _expectLocalFallback(
      timestamp: probe.checkedAt,
      reported: probe.checkedAtReported,
      before: before,
      after: after,
    );
    _expectLocalFallback(
      timestamp: request.at,
      reported: request.atReported,
      before: before,
      after: after,
    );
    _expectLocalFallback(
      timestamp: identity.observedAt,
      reported: identity.observedAtReported,
      before: before,
      after: after,
    );
    expect(probe.toJson(), isNot(contains('checkedAt')));
    expect(request.toJson(), isNot(contains('atMs')));
    expect(identity.toJson(), isNot(contains('observedAt')));
  });

  test('marks invalid timestamps as locally generated', () {
    const invalidTimestamp = 'not-a-timestamp';
    final before = DateTime.now();
    final progress = AiExposureProgress.fromJson(<String, Object?>{
      'updatedAt': invalidTimestamp,
    });
    final history = AiExposureHistoryEntry.fromJson(<String, Object?>{
      'createdAt': invalidTimestamp,
    });
    final result = AiExposureResult.fromJson(<String, Object?>{
      'createdAt': invalidTimestamp,
    });
    final log = AiExposureLogEntry.fromJson(<String, Object?>{
      'at': invalidTimestamp,
    });
    final probe = AiExposureProxyProbeSample.fromJson(<String, Object?>{
      'checkedAt': invalidTimestamp,
    });
    final request = AiExposureProxyRequestSample.fromJson(<String, Object?>{
      'atMs': invalidTimestamp,
    });
    final identity = AiExposureProxyIdentity.fromJson(<String, Object?>{
      'observedAt': invalidTimestamp,
    });
    final after = DateTime.now();

    _expectLocalFallback(
      timestamp: progress.updatedAt,
      reported: progress.updatedAtReported,
      before: before,
      after: after,
    );
    _expectLocalFallback(
      timestamp: history.createdAt,
      reported: history.createdAtReported,
      before: before,
      after: after,
    );
    _expectLocalFallback(
      timestamp: result.createdAt,
      reported: result.createdAtReported,
      before: before,
      after: after,
    );
    _expectLocalFallback(
      timestamp: log.at,
      reported: log.atReported,
      before: before,
      after: after,
    );
    _expectLocalFallback(
      timestamp: probe.checkedAt,
      reported: probe.checkedAtReported,
      before: before,
      after: after,
    );
    _expectLocalFallback(
      timestamp: request.at,
      reported: request.atReported,
      before: before,
      after: after,
    );
    _expectLocalFallback(
      timestamp: identity.observedAt,
      reported: identity.observedAtReported,
      before: before,
      after: after,
    );
  });

  test('timestamp provenance constructor defaults are reported', () {
    final timestamp = DateTime.utc(2026, 8, 7, 12, 34, 56);
    final progress = AiExposureProgress(
      jobId: 'job-1',
      stage: 'queued',
      discovered: 0,
      candidates: 0,
      valid: 0,
      highValue: 0,
      processed: 0,
      total: 0,
      message: '',
      updatedAt: timestamp,
    );
    final history = AiExposureHistoryEntry(
      id: 'history-1',
      name: 'Scan',
      stage: 'queued',
      sources: const <AiExposureSource>[],
      mode: AiExposureScanMode.incremental,
      authorizedScope: const <String>[],
      progress: progress,
      createdAt: timestamp,
    );
    final result = AiExposureResult(
      id: 'result-1',
      jobId: 'job-1',
      source: AiExposureSource.manual,
      url: 'https://example.com',
      host: 'example.com',
      product: 'Example',
      category: AiExposureResultCategory.suspicious,
      credentialState: 'not_found',
      responseFingerprint: '',
      duplicateResponseHosts: 0,
      duplicateKeyHosts: 0,
      modelCount: 0,
      evidence: const <String>[],
      createdAt: timestamp,
    );
    final log = AiExposureLogEntry(
      level: 'info',
      message: 'Started',
      at: timestamp,
    );
    final probe = AiExposureProxyProbeSample(checkedAt: timestamp);
    final request = AiExposureProxyRequestSample(
      at: timestamp,
      result: 'success',
      responseTimeMs: 1,
    );
    final identity = AiExposureProxyIdentity.fromJson(<String, Object?>{
      'observedAt': timestamp.toIso8601String(),
    });

    expect(progress.updatedAtReported, isTrue);
    expect(history.createdAtReported, isTrue);
    expect(result.createdAtReported, isTrue);
    expect(log.atReported, isTrue);
    expect(probe.checkedAtReported, isTrue);
    expect(request.atReported, isTrue);
    expect(identity.observedAtReported, isTrue);
  });
}

void _expectLocalFallback({
  required DateTime timestamp,
  required bool reported,
  required DateTime before,
  required DateTime after,
}) {
  expect(reported, isFalse);
  expect(timestamp.isBefore(before), isFalse);
  expect(timestamp.isAfter(after), isFalse);
}

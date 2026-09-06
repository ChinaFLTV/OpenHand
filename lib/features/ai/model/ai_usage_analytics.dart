import 'dart:convert';

import '../../../shared/util/date_time_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import 'ai_token_usage.dart';

abstract final class AiUsageRequestStatus {
  static const String success = 'success';
  static const String failed = 'failed';
  static const String timeout = 'timeout';
  static const String error = 'error';
  static const String cancelled = 'cancelled';
}

enum AiUsageDataScope {
  proxyOnly('proxy_only'),
  nonProxy('non_proxy'),
  all('all');

  const AiUsageDataScope(this.id);

  final String id;

  static const String proxySource = 'model_proxy';
}

enum AiUsageRange {
  today,
  sevenDays,
  thirtyDays,
  year,
  all;

  DateTime? startAt(DateTime now) {
    return switch (this) {
      AiUsageRange.today => rollingCalendarDateWindow(now).start,
      AiUsageRange.sevenDays => rollingCalendarDateWindow(
        now,
        daysInclusive: kRollingUsageWeekDays,
      ).start,
      AiUsageRange.thirtyDays => rollingCalendarDateWindow(
        now,
        monthsBack: kRollingUsageMonthSpan,
      ).start,
      AiUsageRange.year => rollingCalendarDateWindow(
        now,
        monthsBack: kRollingUsageYearMonths,
      ).start,
      AiUsageRange.all => null,
    };
  }
}

class AiUsageFilter {
  const AiUsageFilter({
    this.range = AiUsageRange.thirtyDays,
    this.providerConfigId,
    this.modelId,
    this.source,
    this.scope = AiUsageDataScope.all,
  });

  final AiUsageRange range;
  final String? providerConfigId;
  final String? modelId;
  final String? source;
  final AiUsageDataScope scope;

  AiUsageFilter copyWith({
    AiUsageRange? range,
    String? providerConfigId,
    bool clearProvider = false,
    String? modelId,
    bool clearModel = false,
    String? source,
    bool clearSource = false,
    AiUsageDataScope? scope,
  }) {
    return AiUsageFilter(
      range: range ?? this.range,
      providerConfigId: clearProvider
          ? null
          : providerConfigId ?? this.providerConfigId,
      modelId: clearModel ? null : modelId ?? this.modelId,
      source: clearSource ? null : source ?? this.source,
      scope: scope ?? this.scope,
    );
  }
}

class AiUsageFacet {
  const AiUsageFacet({required this.value, required this.label});

  final String value;
  final String label;
}

class AiUsageSummary {
  const AiUsageSummary({
    this.requestCount = 0,
    this.successCount = 0,
    this.failureCount = 0,
    this.failedCount = 0,
    this.timeoutCount = 0,
    this.errorCount = 0,
    this.cancelledCount = 0,
    this.estimatedCount = 0,
    this.pricedRequestCount = 0,
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.cacheCreationTokens = 0,
    this.cacheReadTokens = 0,
    this.cacheInputTokens = 0,
    this.reasoningTokens = 0,
    this.audioInputTokens = 0,
    this.imageInputTokens = 0,
    this.videoInputTokens = 0,
    this.totalTokens = 0,
    this.totalCostUsd = 0,
    this.totalDurationMs = 0,
    this.firstTokenDurationMs = 0,
    this.firstTokenSampleCount = 0,
    this.latestContextUsedTokens = 0,
    this.latestContextWindowTokens = 0,
  });

  final int requestCount;
  final int successCount;
  final int failureCount;
  final int failedCount;
  final int timeoutCount;
  final int errorCount;
  final int cancelledCount;
  final int estimatedCount;
  final int pricedRequestCount;
  final int promptTokens;
  final int completionTokens;
  final int cacheCreationTokens;
  final int cacheReadTokens;
  final int cacheInputTokens;
  final int reasoningTokens;
  final int audioInputTokens;
  final int imageInputTokens;
  final int videoInputTokens;
  final int totalTokens;
  final double totalCostUsd;
  final int totalDurationMs;
  final int firstTokenDurationMs;
  final int firstTokenSampleCount;
  final int latestContextUsedTokens;
  final int latestContextWindowTokens;

  double get successRate => requestCount == 0 ? 0 : successCount / requestCount;
  double get cacheHitRate {
    return unitRatio(cacheReadTokens, cacheInputTokens);
  }

  double get averageDurationMs =>
      requestCount == 0 ? 0 : totalDurationMs / requestCount;
  double get averageFirstTokenMs => firstTokenSampleCount == 0
      ? 0
      : firstTokenDurationMs / firstTokenSampleCount;
  bool get hasCompletePricing =>
      requestCount > 0 && pricedRequestCount == requestCount;
}

class AiUsageBucket {
  const AiUsageBucket({
    required this.key,
    required this.requestCount,
    required this.totalTokens,
    required this.totalCostUsd,
    this.pricedRequestCount = 0,
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.cacheCreationTokens = 0,
    this.cacheReadTokens = 0,
    this.successCount = 0,
    this.failedCount = 0,
    this.failureCount = 0,
    this.timeoutCount = 0,
    this.errorCount = 0,
    this.cancelledCount = 0,
  });

  final String key;
  final int requestCount;
  final int totalTokens;
  final double totalCostUsd;
  final int pricedRequestCount;
  final int promptTokens;
  final int completionTokens;
  final int cacheCreationTokens;
  final int cacheReadTokens;
  final int successCount;
  final int failedCount;
  final int failureCount;
  final int timeoutCount;
  final int errorCount;
  final int cancelledCount;
}

class AiUsageBreakdown {
  const AiUsageBreakdown({
    required this.key,
    required this.label,
    required this.requestCount,
    required this.successCount,
    required this.totalTokens,
    required this.totalCostUsd,
    required this.pricedRequestCount,
    required this.averageDurationMs,
    this.failureCount = 0,
    this.timeoutCount = 0,
    this.errorCount = 0,
    this.cancelledCount = 0,
  });

  final String key;
  final String label;
  final int requestCount;
  final int successCount;
  final int totalTokens;
  final double totalCostUsd;
  final int pricedRequestCount;
  final double averageDurationMs;
  final int failureCount;
  final int timeoutCount;
  final int errorCount;
  final int cancelledCount;

  double get successRate => requestCount == 0 ? 0 : successCount / requestCount;
}

class AiUsageRequestRecord {
  AiUsageRequestRecord({
    required this.id,
    required this.traceId,
    required this.startedAt,
    required this.durationMs,
    required this.status,
    required this.surface,
    required this.source,
    required this.operation,
    required this.providerName,
    required this.modelId,
    required this.apiFamily,
    required this.usage,
    required this.totalCostUsd,
    required this.usageEstimated,
    this.sessionId,
    this.threadTemplateId,
    this.firstTokenMs,
    this.errorType,
    this.errorMessage,
    this.httpStatusCode,
    this.timeoutMs,
    this.timeoutPhase,
    this.metadataJson = '{}',
  });

  final String id;
  final String traceId;
  final DateTime startedAt;
  final int durationMs;
  final String status;
  final String surface;
  final String source;
  final String operation;
  final String providerName;
  final String modelId;
  final String apiFamily;
  final AiTokenUsage usage;
  final double? totalCostUsd;
  final bool usageEstimated;
  final String? sessionId;
  final String? threadTemplateId;
  final int? firstTokenMs;
  final String? errorType;
  final String? errorMessage;
  final int? httpStatusCode;
  final int? timeoutMs;
  final String? timeoutPhase;
  final String metadataJson;

  late final Map<String, Object?> _decodedMetadata = _decodeMetadata(
    metadataJson,
  );

  Map<String, Object?> get metadata => _decodedMetadata;

  String metadataText(String key, {String fallback = ''}) {
    final value = metadata[key];
    final text = value is String ? value.trim() : '${value ?? ''}'.trim();
    return text.isEmpty ? fallback : text;
  }

  String get sourceIp =>
      metadataText('source_ip', fallback: metadataText('client_ip'));
  String get sourcePort =>
      metadataText('source_port', fallback: metadataText('client_port'));
  String get sourceEndpoint {
    final ip = sourceIp;
    final port = sourcePort;
    if (ip.isEmpty) return '';
    final host = ip.contains(':') && !ip.startsWith('[') ? '[$ip]' : ip;
    return port.isEmpty ? host : '$host:$port';
  }

  String get userAgent =>
      metadataText('user_agent', fallback: metadataText('client_user_agent'));
  String get processId => metadataText(
    'client_process_pid',
    fallback: metadataText('process_pid', fallback: metadataText('pid')),
  );
  String get processName => metadataText(
    'client_process_name',
    fallback: metadataText('process_name'),
  );
  String get serviceName => metadataText(
    'client_service_name',
    fallback: metadataText('service_name'),
  );
  String get processServiceName {
    final values = <String>{processName, serviceName}
      ..removeWhere((value) => value.isEmpty);
    return values.join(' · ');
  }

  String get macAddress =>
      metadataText('client_mac_address', fallback: metadataText('mac_address'));
  String get clientMetadataSource => metadataText('client_metadata_source');
  String get targetHost =>
      metadataText('target_host', fallback: metadataText('remote_host'));
  String get targetPort =>
      metadataText('target_port', fallback: metadataText('remote_port'));
  String get networkMode =>
      metadataText('network_mode', fallback: metadataText('proxy_mode'));
  String get networkEndpoint => metadataText(
    'network_endpoint',
    fallback: metadataText('proxy_endpoint'),
  );
}

Map<String, Object?> _decodeMetadata(String value) {
  try {
    final decoded = jsonDecode(value);
    if (decoded is Map) {
      return Map<String, Object?>.unmodifiable(<String, Object?>{
        for (final entry in decoded.entries)
          if (entry.key is String) entry.key as String: entry.value,
      });
    }
  } on Object {
    // 历史记录可能没有结构化元数据，按空映射降级。
  }
  return const <String, Object?>{};
}

class AiUsageSnapshot {
  const AiUsageSnapshot({
    required this.generatedAt,
    required this.filter,
    required this.summary,
    required this.trend,
    required this.heatmap,
    required this.providers,
    required this.models,
    required this.sources,
    required this.surfaces,
    required this.operations,
    required this.templates,
    required this.recentRequests,
    required this.providerFacets,
    required this.modelFacets,
    required this.sourceFacets,
    this.proxyRoutes = const <AiUsageBreakdown>[],
    this.healthProviders = const <AiUsageBreakdown>[],
  });

  final DateTime generatedAt;
  final AiUsageFilter filter;
  final AiUsageSummary summary;
  final List<AiUsageBucket> trend;
  final List<AiUsageBucket> heatmap;
  final List<AiUsageBreakdown> providers;
  final List<AiUsageBreakdown> models;
  final List<AiUsageBreakdown> sources;
  final List<AiUsageBreakdown> surfaces;
  final List<AiUsageBreakdown> operations;
  final List<AiUsageBreakdown> templates;
  final List<AiUsageRequestRecord> recentRequests;
  final List<AiUsageFacet> providerFacets;
  final List<AiUsageFacet> modelFacets;
  final List<AiUsageFacet> sourceFacets;
  final List<AiUsageBreakdown> proxyRoutes;
  final List<AiUsageBreakdown> healthProviders;
}

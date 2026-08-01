enum AiExposureServiceLifecycle { stopped, starting, running, stopping, error }

enum AiExposureSource {
  manual('manual'),
  github('github'),
  githubArtifact('github_artifact'),
  gitee('gitee'),
  gitcode('gitcode'),
  fofa('fofa'),
  shodan('shodan');

  const AiExposureSource(this.id);
  final String id;

  static AiExposureSource fromId(String? value) =>
      values.firstWhere((item) => item.id == value, orElse: () => manual);
}

enum AiExposureScanMode { incremental, full }

enum AiExposureValidationMode { passive, authorizedActive }

enum AiExposureResultCategory { valid, suspicious, highValue, honeypot }

enum AiExposureContentEncoding {
  base64('base64'),
  base64Url('base64_url'),
  url('url'),
  hex('hex');

  const AiExposureContentEncoding(this.id);
  final String id;

  static AiExposureContentEncoding? tryFromId(String value) {
    for (final encoding in values) {
      if (encoding.id == value) return encoding;
    }
    return null;
  }
}

enum AiExposureProxyStrategy {
  fixed('fixed'),
  roundRobin('round_robin'),
  random('random'),
  stickyHost('sticky_host');

  const AiExposureProxyStrategy(this.id);
  final String id;

  static AiExposureProxyStrategy fromId(String? value) =>
      values.firstWhere((item) => item.id == value, orElse: () => roundRobin);
}

class AiExposureHealth {
  const AiExposureHealth({
    required this.version,
    required this.databasePath,
    required this.uptimeSeconds,
  });

  factory AiExposureHealth.fromJson(Map<String, Object?> json) =>
      AiExposureHealth(
        version: json['version'] as String? ?? '',
        databasePath: json['databasePath'] as String? ?? '',
        uptimeSeconds: (json['uptimeSeconds'] as num?)?.toInt() ?? 0,
      );

  final String version;
  final String databasePath;
  final int uptimeSeconds;
}

class AiExposureProgress {
  const AiExposureProgress({
    required this.jobId,
    required this.stage,
    required this.discovered,
    required this.candidates,
    required this.valid,
    required this.highValue,
    required this.processed,
    required this.total,
    required this.message,
    required this.updatedAt,
  });

  factory AiExposureProgress.fromJson(Map<String, Object?> json) =>
      AiExposureProgress(
        jobId: json['jobId'] as String? ?? '',
        stage: json['stage'] as String? ?? 'queued',
        discovered: (json['discovered'] as num?)?.toInt() ?? 0,
        candidates: (json['candidates'] as num?)?.toInt() ?? 0,
        valid: (json['valid'] as num?)?.toInt() ?? 0,
        highValue: (json['highValue'] as num?)?.toInt() ?? 0,
        processed: (json['processed'] as num?)?.toInt() ?? 0,
        total: (json['total'] as num?)?.toInt() ?? 0,
        message: json['message'] as String? ?? '',
        updatedAt:
            DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.now(),
      );

  final String jobId;
  final String stage;
  final int discovered;
  final int candidates;
  final int valid;
  final int highValue;
  final int processed;
  final int total;
  final String message;
  final DateTime updatedAt;

  double get fraction => total <= 0 ? 0 : (processed / total).clamp(0, 1);
  bool get isRunning =>
      !const <String>{'completed', 'cancelled', 'failed'}.contains(stage);
}

class AiExposureQuota {
  const AiExposureQuota({
    required this.source,
    required this.configured,
    required this.available,
    required this.message,
    this.remaining,
    this.limit,
    this.resetsAt,
  });

  factory AiExposureQuota.fromJson(Map<String, Object?> json) =>
      AiExposureQuota(
        source: AiExposureSource.fromId(json['source'] as String?),
        configured: json['configured'] as bool? ?? false,
        available: json['available'] as bool? ?? false,
        remaining: (json['remaining'] as num?)?.toInt(),
        limit: (json['limit'] as num?)?.toInt(),
        resetsAt: DateTime.tryParse(json['resetsAt'] as String? ?? ''),
        message: json['message'] as String? ?? '',
      );

  final AiExposureSource source;
  final bool configured;
  final bool available;
  final int? remaining;
  final int? limit;
  final DateTime? resetsAt;
  final String message;
}

class AiExposureScanRule {
  const AiExposureScanRule({
    required this.id,
    required this.vendor,
    required this.protocol,
    required this.enabled,
    required this.credentialPatterns,
    required this.contextTerms,
    this.contentEncodings = const <AiExposureContentEncoding>[],
    required this.modelPaths,
    required this.balancePaths,
  });

  factory AiExposureScanRule.fromJson(Map<String, Object?> json) =>
      AiExposureScanRule(
        id: json['id'] as String? ?? '',
        vendor: json['vendor'] as String? ?? '',
        protocol: json['protocol'] as String? ?? '',
        enabled: json['enabled'] as bool? ?? true,
        credentialPatterns: _stringList(json['credentialPatterns']),
        contextTerms: _stringList(json['contextTerms']),
        contentEncodings: _stringList(json['contentEncodings'])
            .map(AiExposureContentEncoding.tryFromId)
            .whereType<AiExposureContentEncoding>()
            .toList(growable: false),
        modelPaths: _stringList(json['modelPaths']),
        balancePaths: _stringList(json['balancePaths']),
      );

  final String id;
  final String vendor;
  final String protocol;
  final bool enabled;
  final List<String> credentialPatterns;
  final List<String> contextTerms;
  final List<AiExposureContentEncoding> contentEncodings;
  final List<String> modelPaths;
  final List<String> balancePaths;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'vendor': vendor,
    'protocol': protocol,
    'enabled': enabled,
    'credentialPatterns': credentialPatterns,
    'contextTerms': contextTerms,
    'contentEncodings': contentEncodings
        .map((encoding) => encoding.id)
        .toList(growable: false),
    'modelPaths': modelPaths,
    'balancePaths': balancePaths,
  };

  AiExposureScanRule copyWith({
    bool? enabled,
    List<String>? credentialPatterns,
    List<String>? contextTerms,
    List<AiExposureContentEncoding>? contentEncodings,
    List<String>? modelPaths,
    List<String>? balancePaths,
  }) => AiExposureScanRule(
    id: id,
    vendor: vendor,
    protocol: protocol,
    enabled: enabled ?? this.enabled,
    credentialPatterns: credentialPatterns ?? this.credentialPatterns,
    contextTerms: contextTerms ?? this.contextTerms,
    contentEncodings: contentEncodings ?? this.contentEncodings,
    modelPaths: modelPaths ?? this.modelPaths,
    balancePaths: balancePaths ?? this.balancePaths,
  );
}

const int kAiExposureProxyLatencySampleLimit = 24;

class AiExposureProxyProbeSample {
  const AiExposureProxyProbeSample({
    required this.checkedAt,
    this.latencyMs,
    this.statusCode,
    this.error,
  });

  factory AiExposureProxyProbeSample.fromJson(Object? raw) {
    final json = _jsonMap(raw);
    return AiExposureProxyProbeSample(
      checkedAt:
          DateTime.tryParse(json['checkedAt'] as String? ?? '') ??
          DateTime.now(),
      latencyMs: (json['latencyMs'] as num?)?.toInt().clamp(0, 600000),
      statusCode: (json['statusCode'] as num?)?.toInt(),
      error: (json['error'] as String?)?.trim(),
    );
  }

  final DateTime checkedAt;
  final int? latencyMs;
  final int? statusCode;
  final String? error;

  bool get reachable => latencyMs != null && error == null;

  Map<String, Object?> toJson() => <String, Object?>{
    'checkedAt': checkedAt.toIso8601String(),
    if (latencyMs != null) 'latencyMs': latencyMs,
    if (statusCode != null) 'statusCode': statusCode,
    if (error?.isNotEmpty == true) 'error': error,
  };
}

class AiExposureProxyEndpoint {
  const AiExposureProxyEndpoint({
    required this.url,
    this.name = '',
    this.enabled = true,
    this.samples = const <AiExposureProxyProbeSample>[],
  });

  factory AiExposureProxyEndpoint.parse(String input) {
    final value = input.trim();
    if (value.isEmpty ||
        value.length > 2048 ||
        value.contains(RegExp(r'[\r\n]'))) {
      throw const FormatException('代理地址为空或过长。');
    }
    final normalized = value.contains('://') ? value : 'http://$value';
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        !const <String>{'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
        uri.host.isEmpty ||
        !uri.hasPort ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException('代理地址必须为 HTTP/HTTPS 的主机和端口。');
    }
    return AiExposureProxyEndpoint(
      url: uri.replace(scheme: uri.scheme.toLowerCase(), path: '').toString(),
      name: uri.host,
    );
  }

  factory AiExposureProxyEndpoint.fromJson(Object? raw) {
    if (raw is String) return AiExposureProxyEndpoint.parse(raw);
    final json = _jsonMap(raw);
    final endpoint = AiExposureProxyEndpoint.parse(
      json['url'] as String? ?? '',
    );
    final samples = (json['samples'] as List? ?? const <Object?>[])
        .map(AiExposureProxyProbeSample.fromJson)
        .toList(growable: false);
    return endpoint.copyWith(
      name: json['name'] is String ? json['name'] as String : null,
      enabled: json['enabled'] as bool? ?? true,
      samples: samples.length <= kAiExposureProxyLatencySampleLimit
          ? samples
          : samples.sublist(
              samples.length - kAiExposureProxyLatencySampleLimit,
            ),
    );
  }

  final String url;
  final String name;
  final bool enabled;
  final List<AiExposureProxyProbeSample> samples;

  AiExposureProxyProbeSample? get latestSample => samples.lastOrNull;

  String get maskedUrl {
    final uri = Uri.parse(url);
    final host = uri.host.contains(':') ? '[${uri.host}]' : uri.host;
    if (uri.userInfo.isEmpty) return '${uri.scheme}://$host:${uri.port}';
    final username = Uri.decodeComponent(uri.userInfo.split(':').first);
    return '${uri.scheme}://$username:******@$host:${uri.port}';
  }

  String get displayName =>
      name.trim().isEmpty ? Uri.parse(url).host : name.trim();

  AiExposureProxyEndpoint copyWith({
    String? name,
    bool? enabled,
    List<AiExposureProxyProbeSample>? samples,
  }) => AiExposureProxyEndpoint(
    url: url,
    name: name ?? this.name,
    enabled: enabled ?? this.enabled,
    samples: List<AiExposureProxyProbeSample>.unmodifiable(
      samples ?? this.samples,
    ),
  );

  AiExposureProxyEndpoint withSample(AiExposureProxyProbeSample sample) {
    final updated = <AiExposureProxyProbeSample>[...samples, sample];
    if (updated.length > kAiExposureProxyLatencySampleLimit) {
      updated.removeRange(
        0,
        updated.length - kAiExposureProxyLatencySampleLimit,
      );
    }
    return copyWith(samples: updated);
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'url': url,
    if (name.trim().isNotEmpty) 'name': name.trim(),
    'enabled': enabled,
    if (samples.isNotEmpty)
      'samples': samples
          .map((sample) => sample.toJson())
          .toList(growable: false),
  };
}

class AiExposureProxyConfiguration {
  const AiExposureProxyConfiguration({
    required this.enabled,
    required this.strategy,
    required this.rotationEvery,
    required this.bypassLocal,
    required this.endpoints,
    this.inspectionEnabled = false,
    this.inspectionIntervalMinutes = 30,
    this.inspectionConcurrency = 8,
  });

  factory AiExposureProxyConfiguration.defaults() =>
      const AiExposureProxyConfiguration(
        enabled: false,
        strategy: AiExposureProxyStrategy.roundRobin,
        rotationEvery: 1,
        bypassLocal: true,
        endpoints: <AiExposureProxyEndpoint>[],
      );

  factory AiExposureProxyConfiguration.fromJson(Object? raw) {
    final json = _jsonMap(raw);
    final endpoints = <AiExposureProxyEndpoint>[];
    final seen = <String>{};
    for (final value in json['endpoints'] as List? ?? const <Object?>[]) {
      try {
        final endpoint = AiExposureProxyEndpoint.fromJson(value);
        if (seen.add(endpoint.url)) endpoints.add(endpoint);
      } on FormatException {
        continue;
      }
    }
    return AiExposureProxyConfiguration(
      enabled: json['enabled'] as bool? ?? false,
      strategy: AiExposureProxyStrategy.fromId(json['strategy'] as String?),
      rotationEvery: ((json['rotationEvery'] as num?)?.toInt() ?? 1).clamp(
        1,
        10000,
      ),
      bypassLocal: json['bypassLocal'] as bool? ?? true,
      endpoints: List<AiExposureProxyEndpoint>.unmodifiable(endpoints),
      inspectionEnabled: json['inspectionEnabled'] as bool? ?? false,
      inspectionIntervalMinutes:
          ((json['inspectionIntervalMinutes'] as num?)?.toInt() ?? 30).clamp(
            1,
            1440,
          ),
      inspectionConcurrency:
          ((json['inspectionConcurrency'] as num?)?.toInt() ?? 8).clamp(1, 32),
    );
  }

  final bool enabled;
  final AiExposureProxyStrategy strategy;
  final int rotationEvery;
  final bool bypassLocal;
  final List<AiExposureProxyEndpoint> endpoints;
  final bool inspectionEnabled;
  final int inspectionIntervalMinutes;
  final int inspectionConcurrency;

  List<AiExposureProxyEndpoint> get activeEndpoints =>
      endpoints.where((endpoint) => endpoint.enabled).toList(growable: false);

  Map<String, Object?> toJson() => <String, Object?>{
    'enabled': enabled,
    'strategy': strategy.id,
    'rotationEvery': rotationEvery.clamp(1, 10000),
    'bypassLocal': bypassLocal,
    'endpoints': endpoints
        .map((endpoint) => endpoint.toJson())
        .toList(growable: false),
    'inspectionEnabled': inspectionEnabled,
    'inspectionIntervalMinutes': inspectionIntervalMinutes.clamp(1, 1440),
    'inspectionConcurrency': inspectionConcurrency.clamp(1, 32),
  };

  Map<String, Object?> toRuntimeJson() => <String, Object?>{
    'enabled': enabled,
    'strategy': strategy.id,
    'rotationEvery': rotationEvery.clamp(1, 10000),
    'bypassLocal': bypassLocal,
    'endpoints': activeEndpoints
        .map((endpoint) => endpoint.url)
        .toList(growable: false),
  };

  AiExposureProxyConfiguration copyWith({
    bool? enabled,
    AiExposureProxyStrategy? strategy,
    int? rotationEvery,
    bool? bypassLocal,
    List<AiExposureProxyEndpoint>? endpoints,
    bool? inspectionEnabled,
    int? inspectionIntervalMinutes,
    int? inspectionConcurrency,
  }) => AiExposureProxyConfiguration(
    enabled: enabled ?? this.enabled,
    strategy: strategy ?? this.strategy,
    rotationEvery: rotationEvery ?? this.rotationEvery,
    bypassLocal: bypassLocal ?? this.bypassLocal,
    endpoints: List<AiExposureProxyEndpoint>.unmodifiable(
      endpoints ?? this.endpoints,
    ),
    inspectionEnabled: inspectionEnabled ?? this.inspectionEnabled,
    inspectionIntervalMinutes:
        inspectionIntervalMinutes ?? this.inspectionIntervalMinutes,
    inspectionConcurrency: inspectionConcurrency ?? this.inspectionConcurrency,
  );
}

class AiExposureProxyEndpointStatus {
  const AiExposureProxyEndpointStatus({
    required this.id,
    required this.address,
    required this.selections,
  });

  factory AiExposureProxyEndpointStatus.fromJson(Map<String, Object?> json) =>
      AiExposureProxyEndpointStatus(
        id: json['id'] as String? ?? '',
        address: json['address'] as String? ?? '',
        selections: (json['selections'] as num?)?.toInt() ?? 0,
      );

  final String id;
  final String address;
  final int selections;
}

class AiExposureProxyStatus {
  const AiExposureProxyStatus({
    required this.enabled,
    required this.strategy,
    required this.rotationEvery,
    required this.bypassLocal,
    required this.totalSelections,
    required this.endpoints,
  });

  factory AiExposureProxyStatus.fromJson(Map<String, Object?> json) =>
      AiExposureProxyStatus(
        enabled: json['enabled'] as bool? ?? false,
        strategy: AiExposureProxyStrategy.fromId(json['strategy'] as String?),
        rotationEvery: (json['rotationEvery'] as num?)?.toInt() ?? 1,
        bypassLocal: json['bypassLocal'] as bool? ?? true,
        totalSelections: (json['totalSelections'] as num?)?.toInt() ?? 0,
        endpoints: (json['endpoints'] as List? ?? const <Object?>[])
            .map(
              (item) => AiExposureProxyEndpointStatus.fromJson(_jsonMap(item)),
            )
            .toList(growable: false),
      );

  final bool enabled;
  final AiExposureProxyStrategy strategy;
  final int rotationEvery;
  final bool bypassLocal;
  final int totalSelections;
  final List<AiExposureProxyEndpointStatus> endpoints;
}

class AiExposureHistoryEntry {
  const AiExposureHistoryEntry({
    required this.id,
    required this.name,
    required this.stage,
    required this.sources,
    required this.mode,
    required this.authorizedScope,
    required this.progress,
    required this.createdAt,
    this.finishedAt,
    this.errorMessage,
  });

  factory AiExposureHistoryEntry.fromJson(Map<String, Object?> json) =>
      AiExposureHistoryEntry(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        stage: json['stage'] as String? ?? 'queued',
        sources: _stringList(
          json['sources'],
        ).map(AiExposureSource.fromId).toList(growable: false),
        mode: json['mode'] == 'full'
            ? AiExposureScanMode.full
            : AiExposureScanMode.incremental,
        authorizedScope: _stringList(json['authorizedScope']),
        progress: AiExposureProgress.fromJson(_jsonMap(json['progress'])),
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        finishedAt: DateTime.tryParse(json['finishedAt'] as String? ?? ''),
        errorMessage: json['errorMessage'] as String?,
      );

  final String id;
  final String name;
  final String stage;
  final List<AiExposureSource> sources;
  final AiExposureScanMode mode;
  final List<String> authorizedScope;
  final AiExposureProgress progress;
  final DateTime createdAt;
  final DateTime? finishedAt;
  final String? errorMessage;

  bool get isResumable => stage != 'completed';
}

class AiExposureResult {
  const AiExposureResult({
    required this.id,
    required this.jobId,
    required this.source,
    required this.url,
    required this.host,
    required this.product,
    required this.category,
    required this.credentialState,
    required this.responseFingerprint,
    required this.duplicateResponseHosts,
    required this.duplicateKeyHosts,
    required this.modelCount,
    required this.evidence,
    required this.createdAt,
    this.maskedCredential,
    this.balanceSummary,
  });

  factory AiExposureResult.fromJson(Map<String, Object?> json) =>
      AiExposureResult(
        id: json['id'] as String? ?? '',
        jobId: json['jobId'] as String? ?? '',
        source: AiExposureSource.fromId(json['source'] as String?),
        url: json['url'] as String? ?? '',
        host: json['host'] as String? ?? '',
        product: json['product'] as String? ?? '',
        category: switch (json['category']) {
          'valid' => AiExposureResultCategory.valid,
          'high_value' => AiExposureResultCategory.highValue,
          'honeypot' => AiExposureResultCategory.honeypot,
          _ => AiExposureResultCategory.suspicious,
        },
        credentialState: json['credentialState'] as String? ?? 'not_found',
        maskedCredential: json['maskedCredential'] as String?,
        responseFingerprint: json['responseFingerprint'] as String? ?? '',
        duplicateResponseHosts:
            (json['duplicateResponseHosts'] as num?)?.toInt() ?? 0,
        duplicateKeyHosts: (json['duplicateKeyHosts'] as num?)?.toInt() ?? 0,
        modelCount: (json['modelCount'] as num?)?.toInt() ?? 0,
        balanceSummary: json['balanceSummary'] as String?,
        evidence: _stringList(json['evidence']),
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
      );

  final String id;
  final String jobId;
  final AiExposureSource source;
  final String url;
  final String host;
  final String product;
  final AiExposureResultCategory category;
  final String credentialState;
  final String? maskedCredential;
  final String responseFingerprint;
  final int duplicateResponseHosts;
  final int duplicateKeyHosts;
  final int modelCount;
  final String? balanceSummary;
  final List<String> evidence;
  final DateTime createdAt;
}

class AiExposureScanRequest {
  const AiExposureScanRequest({
    required this.name,
    required this.sources,
    required this.mode,
    required this.authorizedScope,
    required this.authorizationConfirmed,
    required this.targets,
    required this.vendors,
    required this.validationMode,
    required this.concurrency,
    required this.gptAssisted,
    this.sourceQueries = const <String, String>{},
  });

  final String name;
  final Set<AiExposureSource> sources;
  final AiExposureScanMode mode;
  final List<String> authorizedScope;
  final bool authorizationConfirmed;
  final List<String> targets;
  final List<String> vendors;
  final AiExposureValidationMode validationMode;
  final int concurrency;
  final bool gptAssisted;
  final Map<String, String> sourceQueries;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'sources': sources.map((source) => source.id).toList(growable: false),
    'mode': mode.name,
    'authorizedScope': authorizedScope,
    'authorizationConfirmed': authorizationConfirmed,
    'targets': targets,
    'vendors': vendors,
    'validationMode':
        validationMode == AiExposureValidationMode.authorizedActive
        ? 'authorized_active'
        : 'passive',
    'concurrency': concurrency,
    'gptAssisted': gptAssisted,
    'sourceQueries': sourceQueries,
  };
}

class AiExposureLogEntry {
  const AiExposureLogEntry({
    required this.level,
    required this.message,
    required this.at,
    this.jobId = '',
  });

  factory AiExposureLogEntry.fromJson(Map<String, Object?> json) =>
      AiExposureLogEntry(
        jobId: json['jobId'] as String? ?? '',
        level: json['level'] as String? ?? 'info',
        message: json['message'] as String? ?? '',
        at: DateTime.tryParse(json['at'] as String? ?? '') ?? DateTime.now(),
      );

  final String jobId;
  final String level;
  final String message;
  final DateTime at;
}

class AiExposureAiExtractorStatus {
  const AiExposureAiExtractorStatus({required this.configured, this.model});

  factory AiExposureAiExtractorStatus.fromJson(Map<String, Object?> json) =>
      AiExposureAiExtractorStatus(
        configured: json['configured'] as bool? ?? false,
        model: json['model'] as String?,
      );

  final bool configured;
  final String? model;
}

class AiExposureDependencyComponentStatus {
  const AiExposureDependencyComponentStatus({
    required this.configured,
    required this.connected,
    required this.message,
  });

  factory AiExposureDependencyComponentStatus.fromJson(
    Map<String, Object?> json,
  ) => AiExposureDependencyComponentStatus(
    configured: json['configured'] as bool? ?? false,
    connected: json['connected'] as bool? ?? false,
    message: json['message'] as String? ?? '',
  );

  final bool configured;
  final bool connected;
  final String message;
}

class AiExposureDependencyStatus {
  const AiExposureDependencyStatus({
    required this.postgresql,
    required this.redis,
  });

  factory AiExposureDependencyStatus.fromJson(Map<String, Object?> json) =>
      AiExposureDependencyStatus(
        postgresql: AiExposureDependencyComponentStatus.fromJson(
          _jsonMap(json['postgresql']),
        ),
        redis: AiExposureDependencyComponentStatus.fromJson(
          _jsonMap(json['redis']),
        ),
      );

  final AiExposureDependencyComponentStatus postgresql;
  final AiExposureDependencyComponentStatus redis;
}

class AiExposurePreferences {
  const AiExposurePreferences({
    required this.enabledSources,
    required this.defaultConcurrency,
    required this.defaultValidationMode,
    required this.defaultGptAssisted,
    required this.useBundledEngine,
    required this.externalAddress,
    required this.proxyConfiguration,
  });

  factory AiExposurePreferences.defaults() => const AiExposurePreferences(
    enabledSources: <AiExposureSource>{
      AiExposureSource.manual,
      AiExposureSource.github,
    },
    defaultConcurrency: 24,
    defaultValidationMode: AiExposureValidationMode.passive,
    defaultGptAssisted: false,
    useBundledEngine: true,
    externalAddress: 'http://127.0.0.1:37821',
    proxyConfiguration: AiExposureProxyConfiguration(
      enabled: false,
      strategy: AiExposureProxyStrategy.roundRobin,
      rotationEvery: 1,
      bypassLocal: true,
      endpoints: <AiExposureProxyEndpoint>[],
    ),
  );

  factory AiExposurePreferences.fromJson(Map<String, Object?> json) {
    final sources = _stringList(
      json['enabledSources'],
    ).map(AiExposureSource.fromId).toSet();
    return AiExposurePreferences(
      enabledSources: sources.isEmpty
          ? const <AiExposureSource>{AiExposureSource.manual}
          : sources,
      defaultConcurrency: ((json['defaultConcurrency'] as num?)?.toInt() ?? 24)
          .clamp(1, 128),
      defaultValidationMode:
          json['defaultValidationMode'] == 'authorized_active'
          ? AiExposureValidationMode.authorizedActive
          : AiExposureValidationMode.passive,
      defaultGptAssisted: json['defaultGptAssisted'] as bool? ?? false,
      useBundledEngine: json['useBundledEngine'] as bool? ?? true,
      externalAddress:
          (json['externalAddress'] as String?)?.trim().isNotEmpty == true
          ? (json['externalAddress'] as String).trim()
          : 'http://127.0.0.1:37821',
      proxyConfiguration: AiExposureProxyConfiguration.fromJson(json['proxy']),
    );
  }

  final Set<AiExposureSource> enabledSources;
  final int defaultConcurrency;
  final AiExposureValidationMode defaultValidationMode;
  final bool defaultGptAssisted;
  final bool useBundledEngine;
  final String externalAddress;
  final AiExposureProxyConfiguration proxyConfiguration;

  Map<String, Object?> toJson() => <String, Object?>{
    'enabledSources': enabledSources
        .map((source) => source.id)
        .toList(growable: false),
    'defaultConcurrency': defaultConcurrency,
    'defaultValidationMode':
        defaultValidationMode == AiExposureValidationMode.authorizedActive
        ? 'authorized_active'
        : 'passive',
    'defaultGptAssisted': defaultGptAssisted,
    'useBundledEngine': useBundledEngine,
    'externalAddress': externalAddress,
    'proxy': proxyConfiguration.toJson(),
  };
}

Map<String, Object?> aiExposureJsonMap(Object? value) => _jsonMap(value);

Map<String, Object?> _jsonMap(Object? value) => value is Map
    ? value.map((key, item) => MapEntry('$key', item))
    : <String, Object?>{};

List<String> _stringList(Object? value) => value is List
    ? value.whereType<Object>().map((item) => '$item').toList(growable: false)
    : const <String>[];

import 'dart:convert';

import 'ai_tool_usage_promotion_store.dart';

enum AiResourceUsagePayloadField {
  arguments,
  result,
  metadata;

  static AiResourceUsagePayloadField? fromName(Object? value) {
    return switch ('$value'.trim()) {
      'arguments' => arguments,
      'result' => result,
      'metadata' => metadata,
      _ => null,
    };
  }

  String get storageValue => switch (this) {
    arguments => 'arguments',
    result => 'result',
    metadata => 'metadata',
  };
}

enum AiResourceUsagePayloadOrigin { stored, persisted, recovered, truncated }

final class AiResourceUsageResolvedPayload {
  const AiResourceUsageResolvedPayload({
    required this.text,
    required this.origin,
  });

  final String text;
  final AiResourceUsagePayloadOrigin origin;

  Map<String, Object?> toJson() => <String, Object?>{
    'text': text,
    'origin': origin.name,
  };
}

final class AiResourceUsagePayloadResolver {
  const AiResourceUsagePayloadResolver({
    required this.store,
    this.loadWorkflowJson,
  });

  final AiToolUsagePromotionStore store;
  final Future<String?> Function(String key)? loadWorkflowJson;

  Future<AiResourceUsageResolvedPayload> resolve({
    required AiResourceUsageEvent event,
    required AiResourceUsagePayloadField field,
  }) async {
    final preview = _previewOf(event, field).trim();
    final persistedPath = _persistedPathOf(event, field);
    if (persistedPath.isNotEmpty) {
      final persisted = await store.readPersistedPayload(persistedPath);
      if (persisted != null) {
        return AiResourceUsageResolvedPayload(
          text: persisted,
          origin: AiResourceUsagePayloadOrigin.persisted,
        );
      }
    }
    if (field == AiResourceUsagePayloadField.result) {
      final toolOutputPath = _toolOutputPath(event.metadataJson);
      if (toolOutputPath != null) {
        final persisted = await store.readPersistedPayload(toolOutputPath);
        if (persisted != null) {
          return AiResourceUsageResolvedPayload(
            text: persisted,
            origin: AiResourceUsagePayloadOrigin.persisted,
          );
        }
      }
    }
    if (usagePayloadLooksClipped(preview)) {
      final recovered = await _recoverWorkflowJson(event, preview);
      if (recovered != null) {
        return AiResourceUsageResolvedPayload(
          text: recovered,
          origin: AiResourceUsagePayloadOrigin.recovered,
        );
      }
      return AiResourceUsageResolvedPayload(
        text: preview,
        origin: AiResourceUsagePayloadOrigin.truncated,
      );
    }
    return AiResourceUsageResolvedPayload(
      text: preview,
      origin: AiResourceUsagePayloadOrigin.stored,
    );
  }

  Future<String?> _recoverWorkflowJson(
    AiResourceUsageEvent event,
    String preview,
  ) async {
    final loader = loadWorkflowJson;
    if (loader == null) return null;
    final seen = <String>{};
    for (final key in _workflowLookupKeys(event, preview)) {
      if (!seen.add(key)) continue;
      final loaded = (await loader(key))?.trim();
      if (loaded != null && loaded.isNotEmpty) return loaded;
    }
    return null;
  }
}

bool usagePayloadLooksClipped(String text) {
  final trimmed = text.trim();
  return trimmed.endsWith('…') || trimmed.endsWith('...');
}

String _previewOf(
  AiResourceUsageEvent event,
  AiResourceUsagePayloadField field,
) {
  return switch (field) {
    AiResourceUsagePayloadField.arguments => event.argumentsSummary,
    AiResourceUsagePayloadField.result => event.resultSummary,
    AiResourceUsagePayloadField.metadata => event.metadataJson,
  };
}

String _persistedPathOf(
  AiResourceUsageEvent event,
  AiResourceUsagePayloadField field,
) {
  return switch (field) {
    AiResourceUsagePayloadField.arguments => event.argumentsFullPath,
    AiResourceUsagePayloadField.result => event.resultFullPath,
    AiResourceUsagePayloadField.metadata => event.metadataFullPath,
  };
}

String? _toolOutputPath(String metadataJson) {
  final raw = metadataJson.trim();
  if (raw.isEmpty || raw == '{}') return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      final path = '${decoded['tool_output_persisted_path'] ?? ''}'.trim();
      if (path.isNotEmpty) return path;
    }
  } catch (_) {}
  return RegExp(
    r'"tool_output_persisted_path"\s*:\s*"([^"]+)"',
  ).firstMatch(raw)?.group(1);
}

Iterable<String> _workflowLookupKeys(
  AiResourceUsageEvent event,
  String preview,
) sync* {
  if (event.kind == AiResourceUsageKind.workflow &&
      event.resourceId.trim().isNotEmpty) {
    yield event.resourceId.trim();
  }
  for (final text in <String>[
    event.argumentsSummary,
    preview,
    event.metadataJson,
  ]) {
    for (final match in _workflowIdPattern.allMatches(text)) {
      final key = match.group(1)?.trim() ?? '';
      if (key.isEmpty) continue;
      if (match.group(0)!.contains('workflow_id') || text.contains('"nodes"')) {
        yield key;
      }
    }
  }
}

final RegExp _workflowIdPattern = RegExp(
  r'"(?:workflow_id|id)"\s*:\s*"([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})"',
);

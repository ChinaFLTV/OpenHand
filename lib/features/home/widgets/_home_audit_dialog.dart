part of '../openhand_home_page.dart';

/// 将类 JSON 值稳定格式化为可读文本。
String _auditFormatJson(Object? value) {
  try {
    return prettyPrintJson(_auditSanitizeValue(value));
  } catch (_) {
    // 无法编码时回退到字符串，保证循环结构等异常数据仍可查看。
    return '${value ?? '—'}';
  }
}

Object? _auditSanitizeValue(Object? value) {
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  if (value is DateTime) {
    return value.toIso8601String();
  }
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        '${entry.key}': _auditSanitizeValue(entry.value),
    };
  }
  if (value is Iterable) {
    return value.map(_auditSanitizeValue).toList(growable: false);
  }
  return value.toString();
}

String _auditFormatInstant(DateTime? value) {
  if (value == null) return '—';
  try {
    final local = value.toLocal();
    final iso = local.toIso8601String();
    return iso;
  } catch (_) {
    return '$value';
  }
}

String _auditFormatBool(bool? value) {
  if (value == null) return '—';
  return value ? 'true' : 'false';
}

String _auditFormatOrDash(Object? value) {
  if (value == null) return '—';
  final text = '$value'.trim();
  return text.isEmpty ? '—' : text;
}

/// 返回单条消息维度的 prefix cache 命中率（0..1）。
/// 与 Token 仪表盘共用 [computeCacheHitRatio] 的协议公式：
/// - Claude / Anthropic：prompt 不含 cache_read/cache_write → 分母 = prompt + read + write。
/// - OpenAI 兼容系 / Gemini：prompt 通常已含 cache_read/cache_write → 分母 = prompt。
/// 返回 null 表示无足够数据（usage 缺失 / 分母为 0）。
double? _auditMessageHitRatio({
  required int? promptTokens,
  required int? cacheReadTokens,
  required int? cacheWriteTokens,
  required bool claudeStyle,
}) {
  final prompt = promptTokens ?? 0;
  final read = cacheReadTokens ?? 0;
  final write = cacheWriteTokens ?? 0;
  if (prompt <= 0 && read <= 0 && write <= 0) return null;
  final ratio = computeCacheHitRatio(
    promptTokens: prompt,
    cacheReadTokens: read,
    cacheWriteTokens: write,
    claudeStyle: claudeStyle,
  );
  final denominator = computeCacheHitDenominatorTokens(
    promptTokens: prompt,
    cacheReadTokens: read,
    cacheWriteTokens: write,
    claudeStyle: claudeStyle,
  );
  return denominator <= 0 ? null : ratio;
}

String _auditFormatHitRatio(double? ratio) {
  if (ratio == null) return '—';
  final percent = (ratio * 100).round();
  return '$percent%';
}

AiSessionMessage? _auditRelatedTelemetryMessage(
  AiSession session,
  AiSessionMessage message,
) {
  if (message.kind != AiSessionMessageKind.user) {
    return null;
  }
  final startIndex = session.messages.indexWhere(
    (item) => item.id == message.id,
  );
  if (startIndex == -1) {
    return null;
  }
  for (var index = startIndex + 1; index < session.messages.length; index++) {
    final candidate = session.messages[index];
    if (candidate.kind == AiSessionMessageKind.user) {
      break;
    }
    if (candidate.isDeleted) {
      continue;
    }
    if (candidate.carriesRequestTelemetry) {
      return candidate;
    }
  }
  return null;
}

const Duration _auditShimmerPeriod = kOpenHandMotion1400;
const double _auditShimmerLineHeight = 14;
const double _auditShimmerLastLineWidth = 180;
const BorderRadius _auditShimmerRadius = kOpenHandBorderRadius6;
const Duration _auditShellSizeDuration = kOpenHandMotion260;
const Duration _auditToggleRotationDuration = kOpenHandMotion200;
const Duration _auditContentSizeDuration = kOpenHandMotion220;
const Curve _auditMotionCurve = kOpenHandEmphasizedTransitionCurve;

/// 审计字段的骨架占位：统一行高、圆角与扫光周期。
Widget _auditShimmerLine({double? width}) {
  return OpenHandSkeletonShimmer(
    width: width,
    height: _auditShimmerLineHeight,
    borderRadius: _auditShimmerRadius,
    period: _auditShimmerPeriod,
  );
}

/// 模拟文本加载状态的微光条。
Widget _auditShimmerBlock({int lines = 3, double spacing = 8}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: List<Widget>.generate(lines, (i) {
      return Padding(
        padding: EdgeInsets.only(bottom: i < lines - 1 ? spacing : 0),
        // 末行更短，读起来更像真实文本。
        child: _auditShimmerLine(
          width: i == lines - 1 ? _auditShimmerLastLineWidth : null,
        ),
      );
    }),
  );
}

/// 平滑处理审计区块展开或折叠引起的弹窗尺寸变化。
class _AuditDialogSizeAnimator extends StatelessWidget {
  const _AuditDialogSizeAnimator({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedSize(
        duration: openHandMotionDuration(context, _auditShellSizeDuration),
        curve: _auditMotionCurve,
        alignment: Alignment.topCenter,
        child: child,
      ),
    );
  }
}

/// 消息与会话审计弹窗共用的区块卡片，可选平滑折叠。
class _AuditSectionCard extends StatefulWidget {
  const _AuditSectionCard({
    required this.title,
    required this.child,
    this.subtitle,
    this.icon,
    this.collapsible = false,
    this.initiallyExpanded = true,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget child;

  /// 正文是否可折叠。
  final bool collapsible;

  /// 可折叠时是否默认展开。
  final bool initiallyExpanded;

  @override
  State<_AuditSectionCard> createState() => _AuditSectionCardState();
}

class _AuditSectionCardState extends State<_AuditSectionCard> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: kOpenHandBorderRadius20,
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: widget.collapsible
                ? () => setState(() => _expanded = !_expanded)
                : null,
            borderRadius: kOpenHandBorderRadius12,
            child: Row(
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, size: 18, color: colorScheme.primary),
                  kOpenHandHGap8,
                ],
                Expanded(
                  child: Text(
                    widget.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (widget.collapsible)
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0.0,
                    duration: openHandMotionDuration(
                      context,
                      _auditToggleRotationDuration,
                    ),
                    curve: _auditMotionCurve,
                    child: Icon(
                      Icons.expand_more_rounded,
                      size: 20,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (widget.subtitle != null) ...[
            kOpenHandGap4,
            Text(
              widget.subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          ClipRect(
            child: AnimatedSize(
              duration: openHandMotionDuration(
                context,
                _auditContentSizeDuration,
              ),
              curve: _auditMotionCurve,
              alignment: Alignment.topLeft,
              child: !widget.collapsible || _expanded
                  ? KeyedSubtree(
                      key: const ValueKey<String>('audit-section-expanded'),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: widget.child,
                      ),
                    )
                  : const KeyedSubtree(
                      key: ValueKey<String>('audit-section-collapsed'),
                      child: SizedBox(width: double.infinity, height: 0),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 审计弹窗键值行，值可单独选择复制。
class _AuditKvRow extends StatelessWidget {
  const _AuditKvRow({
    required this.label,
    this.value,
    this.valueWidget,
    this.mono = false,
  }) : assert(value != null || valueWidget != null);

  final String label;
  final String? value;

  /// 替代文本值的可选组件，用于流式微光占位。
  final Widget? valueWidget;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final valueStyle =
        (mono
                ? theme.textTheme.bodySmall?.copyWith(
                    fontFamily: kOpenHandMonospaceFontFamily,
                  )
                : theme.textTheme.bodyMedium)
            ?.copyWith(color: colorScheme.onSurface);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          kOpenHandHGap12,
          Expanded(
            child:
                valueWidget ??
                SelectableText(
                  (value ?? '').isEmpty ? '—' : value!,
                  style: valueStyle,
                ),
          ),
        ],
      ),
    );
  }
}

/// 支持复制并可平滑折叠的 JSON 区块。
class _AuditJsonBlock extends StatefulWidget {
  const _AuditJsonBlock({
    required this.label,
    required this.json,
    this.initiallyExpanded = false,
    this.emptyHint,
  });

  final String label;
  final Object? json;
  final bool initiallyExpanded;
  final String? emptyHint;

  @override
  State<_AuditJsonBlock> createState() => _AuditJsonBlockState();
}

class _AuditJsonBlockState extends State<_AuditJsonBlock> {
  late bool _expanded = widget.initiallyExpanded;

  bool get _isEmpty {
    final value = widget.json;
    if (value == null) return true;
    if (value is Map && value.isEmpty) return true;
    if (value is Iterable && value.isEmpty) return true;
    if (value is String && value.trim().isEmpty) return true;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final rendered = _isEmpty ? '' : _auditFormatJson(widget.json);
    final emptyHint =
        widget.emptyHint ?? AppLocalizations.of(context)!.auditNoData;
    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: kOpenHandBorderRadius14,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: _isEmpty
                ? null
                : () => setState(() => _expanded = !_expanded),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(kOpenHandRadius14),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0.0,
                    duration: openHandMotionDuration(
                      context,
                      _auditToggleRotationDuration,
                    ),
                    curve: _auditMotionCurve,
                    child: Icon(
                      Icons.expand_more_rounded,
                      size: 18,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  kOpenHandHGap6,
                  Expanded(
                    child: Text(
                      widget.label,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (!_isEmpty)
                    IconButton(
                      tooltip: AppLocalizations.of(context)!.auditCopyJson,
                      icon: const Icon(Icons.copy_all_rounded, size: 18),
                      onPressed: () async {
                        await copyOpenHandTextToClipboard(
                          logTag: 'home',
                          context: context,
                          text: rendered,
                          successMessage: AppLocalizations.of(
                            context,
                          )!.auditCopiedToClipboard,
                          logAction: '复制审计 JSON',
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
          if (_isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Text(
                emptyHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            ClipRect(
              child: AnimatedSize(
                duration: openHandMotionDuration(
                  context,
                  _auditContentSizeDuration,
                ),
                curve: _auditMotionCurve,
                alignment: Alignment.topLeft,
                child: _expanded
                    ? KeyedSubtree(
                        key: const ValueKey<String>('audit-json-expanded'),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                          child: SelectableText(
                            rendered,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: kOpenHandMonospaceFontFamily,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ),
                      )
                    : const KeyedSubtree(
                        key: ValueKey<String>('audit-json-collapsed'),
                        child: SizedBox.shrink(),
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 消息级审计弹窗，展示原始响应、参数、耗时、错误和遥测信息。
class _MessageAuditDialog extends StatefulWidget {
  const _MessageAuditDialog({
    required this.message,
    required this.session,
    required this.controller,
    required this.claudeStyle,
  });

  final AiSessionMessage message;
  final AiSession session;
  final AiSessionController controller;
  final bool claudeStyle;

  @override
  State<_MessageAuditDialog> createState() => _MessageAuditDialogState();
}

class _MessageAuditDialogState extends State<_MessageAuditDialog> {
  bool _rebuildScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    if (_rebuildScheduled) {
      return;
    }
    _rebuildScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rebuildScheduled = false;
      if (!mounted) return;
      setState(() {});
    });
  }

  AiSession get _liveSession {
    for (final session in widget.controller.sessions) {
      if (session.id == widget.session.id) {
        return session;
      }
    }
    return widget.session;
  }

  AiSessionMessage get _liveMessage {
    final session = _liveSession;
    for (final message in session.messages) {
      if (message.id == widget.message.id) {
        return message;
      }
    }
    return widget.message;
  }

  @override
  Widget build(BuildContext context) {
    final session = _liveSession;
    final message = _liveMessage;
    final relatedMessage = _auditRelatedTelemetryMessage(session, message);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final size = MediaQuery.sizeOf(context);
    final maxWidth = size.width * 0.88;
    final maxHeight = size.height * 0.88;
    final metadata = Map<String, Object?>.from(message.metadata);
    final relatedMetadata = relatedMessage == null
        ? const <String, Object?>{}
        : Map<String, Object?>.from(relatedMessage.metadata);
    // 提取已知遥测结构。
    final telemetry = metadata['telemetry'];
    final relatedTelemetry = relatedMetadata['telemetry'];
    final durationMs = _auditFirstInt([
      metadata['duration_ms'],
      if (telemetry is Map) telemetry['duration_ms'],
      relatedMetadata['duration_ms'],
      if (relatedTelemetry is Map) relatedTelemetry['duration_ms'],
    ]);
    final startedAt = _auditFirstDate([
      metadata['started_at'],
      if (telemetry is Map) telemetry['started_at'],
      relatedMetadata['started_at'],
      if (relatedTelemetry is Map) relatedTelemetry['started_at'],
    ]);
    final endedAt = _auditFirstDate([
      metadata['ended_at'],
      metadata['completed_at'],
      if (telemetry is Map) telemetry['ended_at'],
      relatedMetadata['ended_at'],
      relatedMetadata['completed_at'],
      if (relatedTelemetry is Map) relatedTelemetry['ended_at'],
    ]);
    final error = _auditFirstString([
      metadata['error'],
      metadata['error_message'],
      if (telemetry is Map) telemetry['error'],
      relatedMetadata['error'],
      relatedMetadata['error_message'],
      if (relatedTelemetry is Map) relatedTelemetry['error'],
    ]);
    final sendPreflightElapsedMs = _auditFirstInt([
      metadata['send_preflight_elapsed_ms'],
      relatedMetadata['send_preflight_elapsed_ms'],
    ]);
    final preRequestElapsedMs = _auditFirstInt([
      metadata['request_start_elapsed_ms'],
      metadata['pre_request_elapsed_ms'],
      relatedMetadata['request_start_elapsed_ms'],
      relatedMetadata['pre_request_elapsed_ms'],
    ]);
    final sendPreflightTimings = _auditFirstMap([
      metadata['send_preflight_timings_ms'],
      relatedMetadata['send_preflight_timings_ms'],
    ]);
    final preRequestTimings = _auditFirstMap([
      metadata['pre_request_timings_ms'],
      relatedMetadata['pre_request_timings_ms'],
    ]);
    final requestUrl = _auditFirstString([
      metadata['request_url'],
      if (telemetry is Map) telemetry['request_url'],
      relatedMetadata['request_url'],
      if (relatedTelemetry is Map) relatedTelemetry['request_url'],
    ]);
    final requestMethod = _auditFirstString([
      metadata['request_method'],
      if (telemetry is Map) telemetry['request_method'],
      relatedMetadata['request_method'],
      if (relatedTelemetry is Map) relatedTelemetry['request_method'],
    ]);
    final requestHeaders = _auditFirstMap([
      metadata['request_headers'],
      if (telemetry is Map) telemetry['request_headers'],
      relatedMetadata['request_headers'],
      if (relatedTelemetry is Map) relatedTelemetry['request_headers'],
    ]);
    final requestPayload = _auditFirstAny([
      metadata['request_payload'],
      metadata['request_body'],
      if (telemetry is Map) telemetry['request_payload'],
      relatedMetadata['request_payload'],
      relatedMetadata['request_body'],
      if (relatedTelemetry is Map) relatedTelemetry['request_payload'],
    ]);
    final requestFallbacks = _auditFirstList([
      metadata['request_fallbacks'],
      if (telemetry is Map) telemetry['request_fallbacks'],
      relatedMetadata['request_fallbacks'],
      if (relatedTelemetry is Map) relatedTelemetry['request_fallbacks'],
    ]);
    final responseRaw = _auditFirstAny([
      metadata['response_raw'],
      metadata['raw_response'],
      if (telemetry is Map) telemetry['response_raw'],
      relatedMetadata['response_raw'],
      relatedMetadata['raw_response'],
      if (relatedTelemetry is Map) relatedTelemetry['response_raw'],
    ]);
    final envSnapshot = _auditFirstMap([
      metadata['environment'],
      if (telemetry is Map) telemetry['environment'],
      relatedMetadata['environment'],
      if (relatedTelemetry is Map) relatedTelemetry['environment'],
    ]);
    final attachments = _auditFirstList([
      metadata['attachments'],
      if (telemetry is Map) telemetry['attachments'],
      relatedMetadata['attachments'],
      if (relatedTelemetry is Map) relatedTelemetry['attachments'],
    ]);
    final streaming = metadata[aiSessionMessageMetadataStreamingKey] == true;
    final telemetryInFlight =
        metadata[aiSessionMessageTelemetryInFlightMetadataKey] == true ||
        relatedMetadata[aiSessionMessageTelemetryInFlightMetadataKey] == true;
    final waitingForTelemetry = streaming || telemetryInFlight;
    final displayUsage = message.usage ?? relatedMessage?.usage;
    final displayModelId = message.modelId ?? relatedMessage?.modelId;
    final displayModelLabel = message.modelLabel ?? relatedMessage?.modelLabel;
    final estimatedPromptTokens = _auditFirstInt([
      metadata['estimated_prompt_tokens'],
      relatedMetadata['estimated_prompt_tokens'],
    ]);
    final estimatedTotalTokens = _auditFirstInt([
      metadata['estimated_total_tokens'],
      relatedMetadata['estimated_total_tokens'],
      estimatedPromptTokens,
    ]);
    // 遥测调试开启时保存的实际发送提示词正文。
    final composedPromptText = _auditFirstString([
      metadata['composed_prompt_text'],
    ]);
    final composedPromptTurns = _auditFirstList([
      metadata['composed_prompt_turns'],
    ]);
    final promptMetadataFromMsg = _auditFirstMap([metadata['prompt_metadata']]);
    final cacheIdleGapSeconds = _auditFirstInt([
      metadata['idle_gap_seconds'],
      relatedMetadata['idle_gap_seconds'],
      if (promptMetadataFromMsg != null)
        promptMetadataFromMsg['idle_gap_seconds'],
    ]);
    final cacheTtlSuspected = _auditFirstBool([
      metadata['ttl_suspected'],
      relatedMetadata['ttl_suspected'],
      if (promptMetadataFromMsg != null) promptMetadataFromMsg['ttl_suspected'],
    ]);
    final stablePrefixHash = _auditFirstString([
      metadata['stable_prefix_hash'],
      relatedMetadata['stable_prefix_hash'],
      if (promptMetadataFromMsg != null)
        promptMetadataFromMsg['stable_prefix_hash'],
    ]);
    final previousStablePrefixHash = _auditFirstString([
      metadata['previous_stable_prefix_hash'],
      relatedMetadata['previous_stable_prefix_hash'],
      if (promptMetadataFromMsg != null)
        promptMetadataFromMsg['previous_stable_prefix_hash'],
    ]);
    final toolCatalogHash = _auditFirstString([
      metadata['tool_catalog_hash'],
      relatedMetadata['tool_catalog_hash'],
      if (promptMetadataFromMsg != null)
        promptMetadataFromMsg['tool_catalog_hash'],
    ]);
    final previousToolCatalogHash = _auditFirstString([
      metadata['previous_tool_catalog_hash'],
      relatedMetadata['previous_tool_catalog_hash'],
      if (promptMetadataFromMsg != null)
        promptMetadataFromMsg['previous_tool_catalog_hash'],
    ]);
    final cacheControlStrategy = _auditFirstString([
      metadata['cache_control_strategy'],
      relatedMetadata['cache_control_strategy'],
      if (promptMetadataFromMsg != null)
        promptMetadataFromMsg['cache_control_strategy'],
    ]);
    final automaticProviderCacheProtected = _auditFirstBool([
      metadata['cache_provider_automatic_cache_protected'],
      relatedMetadata['cache_provider_automatic_cache_protected'],
      if (promptMetadataFromMsg != null)
        promptMetadataFromMsg['cache_provider_automatic_cache_protected'],
    ]);
    final automaticProviderCacheBestEffort =
        _auditFirstBool([
          metadata['cache_provider_automatic_cache_best_effort'],
          relatedMetadata['cache_provider_automatic_cache_best_effort'],
          if (promptMetadataFromMsg != null)
            promptMetadataFromMsg['cache_provider_automatic_cache_best_effort'],
        ]) ||
        cacheControlStrategy == 'automatic_provider_cache';
    final protocolControlled =
        _auditFirstBool([
          metadata['cache_protocol_controlled'],
          relatedMetadata['cache_protocol_controlled'],
          if (promptMetadataFromMsg != null)
            promptMetadataFromMsg['cache_protocol_controlled'],
        ]) ||
        cacheControlStrategy == 'explicit_cache_control';
    final cacheAffinityDegraded = _auditFirstBool([
      metadata['cache_affinity_degraded'],
      relatedMetadata['cache_affinity_degraded'],
      if (promptMetadataFromMsg != null)
        promptMetadataFromMsg['cache_affinity_degraded'],
    ]);
    final stableCacheKey = _auditFirstString([
      metadata['stable_cache_key'],
      relatedMetadata['stable_cache_key'],
      if (promptMetadataFromMsg != null)
        promptMetadataFromMsg['stable_cache_key'],
    ]);
    final previousStableCacheKey = _auditFirstString([
      metadata['previous_stable_cache_key'],
      relatedMetadata['previous_stable_cache_key'],
      if (promptMetadataFromMsg != null)
        promptMetadataFromMsg['previous_stable_cache_key'],
    ]);
    final cacheHitRatio = displayUsage == null
        ? null
        : _auditMessageHitRatio(
            promptTokens: displayUsage.promptTokens,
            cacheReadTokens: displayUsage.cacheReadTokens,
            cacheWriteTokens: displayUsage.cacheCreationTokens,
            claudeStyle: widget.claudeStyle,
          );
    final stablePrefixKnown =
        stablePrefixHash != null &&
        previousStablePrefixHash != null &&
        stablePrefixHash.isNotEmpty &&
        previousStablePrefixHash.isNotEmpty;
    final stablePrefixUnchanged =
        stablePrefixKnown && stablePrefixHash == previousStablePrefixHash;
    final toolCatalogStable =
        toolCatalogHash == null ||
        previousToolCatalogHash == null ||
        toolCatalogHash.isEmpty ||
        previousToolCatalogHash.isEmpty ||
        toolCatalogHash == previousToolCatalogHash;
    final automaticProviderMissSuspected =
        !protocolControlled &&
        (automaticProviderCacheProtected || automaticProviderCacheBestEffort) &&
        !cacheTtlSuspected &&
        stablePrefixUnchanged &&
        toolCatalogStable &&
        cacheIdleGapSeconds != null &&
        cacheIdleGapSeconds >= kAutomaticProviderCacheMissMinGapSeconds &&
        cacheHitRatio != null &&
        cacheHitRatio < kAutomaticProviderCacheMissHitRatioThreshold;
    final prefixDriftSuspected =
        !cacheTtlSuspected &&
        !automaticProviderMissSuspected &&
        cacheIdleGapSeconds != null &&
        cacheIdleGapSeconds < 3600 &&
        ((stablePrefixKnown && stablePrefixHash != previousStablePrefixHash) ||
            (toolCatalogHash != null &&
                previousToolCatalogHash != null &&
                toolCatalogHash.isNotEmpty &&
                previousToolCatalogHash.isNotEmpty &&
                toolCatalogHash != previousToolCatalogHash));

    return _AuditDialogSizeAnimator(
      child: buildOpenHandAlertDialog(
        backgroundColor: colorScheme.surfaceContainerHighest,
        surfaceTintColor: Colors.transparent,
        titlePadding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
        contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        shape: const RoundedRectangleBorder(
          borderRadius: kOpenHandBorderRadius26,
        ),
        title: Row(
          children: [
            Icon(Icons.fact_check_outlined, color: colorScheme.primary),
            kOpenHandHGap10,
            Expanded(
              child: Text(
                AppLocalizations.of(context)!.auditMessageAudit,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            IconButton(
              tooltip: AppLocalizations.of(context)!.auditClose,
              icon: const Icon(Icons.close_rounded),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _AuditSectionCard(
                  icon: Icons.info_outline_rounded,
                  title: AppLocalizations.of(context)!.auditOverview,
                  child: Column(
                    children: [
                      _AuditKvRow(
                        label: AppLocalizations.of(context)!.auditMessageId,
                        value: message.id,
                        mono: true,
                      ),
                      _AuditKvRow(
                        label: AppLocalizations.of(context)!.auditSessionId,
                        value: session.id,
                        mono: true,
                      ),
                      _AuditKvRow(
                        label: AppLocalizations.of(context)!.auditRole,
                        value: message.role.storageValue,
                      ),
                      _AuditKvRow(
                        label: AppLocalizations.of(context)!.auditKind,
                        value: message.kind.storageValue,
                      ),
                      _AuditKvRow(
                        label: AppLocalizations.of(
                          context,
                        )!.auditCharacterCount,
                        value: '${message.characterCount}',
                      ),
                      _AuditKvRow(
                        label: AppLocalizations.of(context)!.auditStreaming,
                        value: _auditFormatBool(streaming),
                      ),
                      _AuditKvRow(
                        label: AppLocalizations.of(context)!.auditDeleted,
                        value: _auditFormatBool(message.isDeleted),
                      ),
                      _AuditKvRow(
                        label: AppLocalizations.of(context)!.auditHasError,
                        value: _auditFormatBool(
                          error != null && error.isNotEmpty,
                        ),
                      ),
                    ],
                  ),
                ),
                _AuditSectionCard(
                  icon: Icons.schedule_outlined,
                  title: AppLocalizations.of(context)!.auditTiming,
                  child: Column(
                    children: [
                      _AuditKvRow(
                        label: AppLocalizations.of(
                          context,
                        )!.auditStartedCreated,
                        value: _auditFormatInstant(
                          startedAt ?? message.createdAt,
                        ),
                      ),
                      if (waitingForTelemetry && endedAt == null)
                        _AuditKvRow(
                          label: AppLocalizations.of(context)!.auditEnded,
                          valueWidget: _auditShimmerLine(width: 200),
                        )
                      else
                        _AuditKvRow(
                          label: AppLocalizations.of(context)!.auditEnded,
                          value: _auditFormatInstant(endedAt),
                        ),
                      if (waitingForTelemetry && durationMs == null)
                        _AuditKvRow(
                          label: AppLocalizations.of(context)!.auditDurationMs,
                          valueWidget: _auditShimmerLine(width: 120),
                        )
                      else
                        _AuditKvRow(
                          label: AppLocalizations.of(context)!.auditDurationMs,
                          value: durationMs == null ? '—' : '$durationMs',
                        ),
                      if (sendPreflightElapsedMs != null)
                        _AuditKvRow(
                          label: openHandLocalizedText(
                            context,
                            zh: '发送前耗时 (ms)',
                            zhHant: '送出前耗時 (ms)',
                            en: 'Send Preflight (ms)',
                            fr: 'Pré-envoi (ms)',
                            de: 'Vor dem Senden (ms)',
                            ja: '送信前処理 (ms)',
                          ),
                          value: '$sendPreflightElapsedMs',
                        ),
                      if (preRequestElapsedMs != null)
                        _AuditKvRow(
                          label: openHandLocalizedText(
                            context,
                            zh: '请求前耗时 (ms)',
                            zhHant: '請求前耗時 (ms)',
                            en: 'Pre-request (ms)',
                            fr: 'Avant requête (ms)',
                            de: 'Vor Anfrage (ms)',
                            ja: 'リクエスト前 (ms)',
                          ),
                          value: '$preRequestElapsedMs',
                        ),
                      if (sendPreflightTimings != null &&
                          sendPreflightTimings.isNotEmpty) ...[
                        kOpenHandGap10,
                        _AuditJsonBlock(
                          label: openHandLocalizedText(
                            context,
                            zh: '发送前阶段耗时',
                            zhHant: '送出前階段耗時',
                            en: 'Send Preflight Timings',
                            fr: 'Durées de pré-envoi',
                            de: 'Vor-Senden-Zeiten',
                            ja: '送信前処理の時間',
                          ),
                          json: sendPreflightTimings,
                        ),
                      ],
                      if (preRequestTimings != null &&
                          preRequestTimings.isNotEmpty) ...[
                        kOpenHandGap10,
                        _AuditJsonBlock(
                          label: openHandLocalizedText(
                            context,
                            zh: '请求前阶段耗时',
                            zhHant: '請求前階段耗時',
                            en: 'Pre-request Timings',
                            fr: 'Durées avant requête',
                            de: 'Vor-Anfrage-Zeiten',
                            ja: 'リクエスト前の時間',
                          ),
                          json: preRequestTimings,
                        ),
                      ],
                    ],
                  ),
                ),
                _AuditSectionCard(
                  icon: Icons.memory_outlined,
                  title: AppLocalizations.of(context)!.auditModelTokens,
                  child: Column(
                    children: [
                      _AuditKvRow(
                        label: AppLocalizations.of(context)!.auditModelId,
                        value: _auditFormatOrDash(displayModelId),
                      ),
                      _AuditKvRow(
                        label: AppLocalizations.of(context)!.auditModelLabel,
                        value: _auditFormatOrDash(displayModelLabel),
                      ),
                      if (waitingForTelemetry && displayUsage == null) ...[
                        _AuditKvRow(
                          label: AppLocalizations.of(context)!.auditTotalTokens,
                          value: estimatedTotalTokens == null
                              ? null
                              : '~$estimatedTotalTokens',
                          valueWidget: estimatedTotalTokens == null
                              ? _auditShimmerLine(width: 100)
                              : null,
                        ),
                        _AuditKvRow(
                          label: AppLocalizations.of(
                            context,
                          )!.auditPromptTokens,
                          value: estimatedPromptTokens == null
                              ? null
                              : '~$estimatedPromptTokens',
                          valueWidget: estimatedPromptTokens == null
                              ? _auditShimmerLine(width: 100)
                              : null,
                        ),
                        _AuditKvRow(
                          label: AppLocalizations.of(
                            context,
                          )!.auditCompletionTokens,
                          valueWidget: _auditShimmerLine(width: 100),
                        ),
                      ] else ...[
                        _AuditKvRow(
                          label: AppLocalizations.of(context)!.auditTotalTokens,
                          value:
                              '${displayUsage?.totalTokens ?? (estimatedTotalTokens == null ? '—' : '~$estimatedTotalTokens')}',
                        ),
                        _AuditKvRow(
                          label: AppLocalizations.of(
                            context,
                          )!.auditPromptTokens,
                          value:
                              '${displayUsage?.promptTokens ?? (estimatedPromptTokens == null ? '—' : '~$estimatedPromptTokens')}',
                        ),
                        _AuditKvRow(
                          label: AppLocalizations.of(
                            context,
                          )!.auditCompletionTokens,
                          value: '${displayUsage?.completionTokens ?? '—'}',
                        ),
                        if ((displayUsage?.reasoningTokens ?? 0) > 0)
                          _AuditKvRow(
                            label: AppLocalizations.of(
                              context,
                            )!.tokenPopupReasoning,
                            value: '${displayUsage!.reasoningTokens}',
                          ),
                        if ((displayUsage?.cacheReadTokens ?? 0) > 0)
                          _AuditKvRow(
                            label: AppLocalizations.of(
                              context,
                            )!.tokenPopupCacheRead,
                            value: '${displayUsage!.cacheReadTokens}',
                          ),
                        if ((displayUsage?.cacheCreationTokens ?? 0) > 0)
                          _AuditKvRow(
                            label: AppLocalizations.of(
                              context,
                            )!.tokenPopupCacheWrite,
                            value: '${displayUsage!.cacheCreationTokens}',
                          ),
                        if (displayUsage != null &&
                            _auditMessageHitRatio(
                                  promptTokens: displayUsage.promptTokens,
                                  cacheReadTokens: displayUsage.cacheReadTokens,
                                  cacheWriteTokens:
                                      displayUsage.cacheCreationTokens,
                                  claudeStyle: widget.claudeStyle,
                                ) !=
                                null)
                          _AuditKvRow(
                            label: AppLocalizations.of(
                              context,
                            )!.auditCacheHitRatio,
                            value: _auditFormatHitRatio(
                              _auditMessageHitRatio(
                                promptTokens: displayUsage.promptTokens,
                                cacheReadTokens: displayUsage.cacheReadTokens,
                                cacheWriteTokens:
                                    displayUsage.cacheCreationTokens,
                                claudeStyle: widget.claudeStyle,
                              ),
                            ),
                          ),
                      ],
                      if (displayUsage != null)
                        _AuditJsonBlock(
                          label: AppLocalizations.of(
                            context,
                          )!.auditTokenBreakdown,
                          json: displayUsage.toJson(),
                        ),
                      if (cacheIdleGapSeconds != null ||
                          cacheTtlSuspected ||
                          prefixDriftSuspected ||
                          automaticProviderMissSuspected ||
                          cacheAffinityDegraded)
                        _AuditJsonBlock(
                          label: openHandLocalizedText(
                            context,
                            zh: '缓存诊断',
                            zhHant: '快取診斷',
                            en: 'Cache Diagnostics',
                            fr: 'Diagnostics du cache',
                            de: 'Cache-Diagnose',
                            ja: 'キャッシュ診断',
                          ),
                          initiallyExpanded: true,
                          json: <String, Object?>{
                            'idle_gap_seconds': cacheIdleGapSeconds,
                            'ttl_suspected': cacheTtlSuspected,
                            'prefix_drift_suspected': prefixDriftSuspected,
                            'automatic_provider_cache_miss_suspected':
                                automaticProviderMissSuspected,
                            'cache_affinity_degraded': cacheAffinityDegraded,
                            'stable_prefix_hash': stablePrefixHash,
                            'previous_stable_prefix_hash':
                                previousStablePrefixHash,
                            'tool_catalog_hash': toolCatalogHash,
                            'previous_tool_catalog_hash':
                                previousToolCatalogHash,
                            'cache_control_strategy': cacheControlStrategy,
                            'stable_cache_key': stableCacheKey,
                            'previous_stable_cache_key': previousStableCacheKey,
                          },
                        ),
                    ],
                  ),
                ),
                if (error != null && error.isNotEmpty)
                  _AuditSectionCard(
                    icon: Icons.error_outline_rounded,
                    title: AppLocalizations.of(context)!.auditError,
                    child: SelectableText(
                      error,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.error,
                        fontFamily: kOpenHandMonospaceFontFamily,
                      ),
                    ),
                  ),
                _AuditSectionCard(
                  icon: Icons.article_outlined,
                  collapsible: true,
                  initiallyExpanded: false,
                  title: AppLocalizations.of(context)!.auditContent,
                  subtitle: composedPromptText != null
                      ? AppLocalizations.of(
                          context,
                        )!.auditFullComposedPromptThatWasActually
                      : streaming
                      ? AppLocalizations.of(
                          context,
                        )!.auditWaitingForComposedPromptInjectionAuto
                      : null,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colorScheme.surface,
                          borderRadius: kOpenHandBorderRadius12,
                        ),
                        child:
                            waitingForTelemetry &&
                                (composedPromptText == null ||
                                    composedPromptText.isEmpty)
                            ? _auditShimmerBlock(lines: 6)
                            : SelectableText(
                                composedPromptText != null &&
                                        composedPromptText.isNotEmpty
                                    ? composedPromptText
                                    : (message.content.isEmpty
                                          ? '—'
                                          : message.content),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontFamily: kOpenHandMonospaceFontFamily,
                                ),
                              ),
                      ),
                      if (composedPromptText != null) ...[
                        kOpenHandGap10,
                        _AuditKvRow(
                          label: AppLocalizations.of(
                            context,
                          )!.auditUserRawInput,
                          value: message.content.isEmpty
                              ? '—'
                              : message.content,
                          mono: true,
                        ),
                        if (composedPromptTurns != null &&
                            composedPromptTurns.isNotEmpty)
                          _AuditJsonBlock(
                            label: AppLocalizations.of(
                              context,
                            )!.auditStructuredPromptTurns,
                            json: composedPromptTurns,
                            emptyHint: AppLocalizations.of(context)!.auditNone,
                          ),
                        if (promptMetadataFromMsg != null &&
                            promptMetadataFromMsg.isNotEmpty)
                          _AuditJsonBlock(
                            label: AppLocalizations.of(
                              context,
                            )!.auditPromptMetadata,
                            json: promptMetadataFromMsg,
                          ),
                      ],
                    ],
                  ),
                ),
                _AuditSectionCard(
                  icon: Icons.cloud_outlined,
                  collapsible: true,
                  initiallyExpanded: false,
                  title: AppLocalizations.of(context)!.auditRequest,
                  child: Column(
                    children: [
                      _AuditKvRow(
                        label: 'URL',
                        value: _auditFormatOrDash(requestUrl),
                        mono: true,
                      ),
                      _AuditKvRow(
                        label: AppLocalizations.of(context)!.auditMethod,
                        value: _auditFormatOrDash(requestMethod),
                      ),
                      if (requestFallbacks != null &&
                          requestFallbacks.isNotEmpty)
                        _AuditJsonBlock(
                          label: openHandLocalizedText(
                            context,
                            zh: '路由与兼容性调整',
                            zhHant: '路由與相容性調整',
                            en: 'Routing and Compatibility Adjustments',
                            fr: 'Ajustements de routage et de compatibilité',
                            de: 'Routing- und Kompatibilitätsanpassungen',
                            ja: 'ルーティングと互換性の調整',
                          ),
                          json: requestFallbacks,
                          initiallyExpanded: true,
                        ),
                      _AuditJsonBlock(
                        label: AppLocalizations.of(context)!.auditHeaders,
                        json: requestHeaders,
                        emptyHint: AppLocalizations.of(
                          context,
                        )!.auditNotCapturedEnableSettingsAiTelemetry,
                      ),
                      _AuditJsonBlock(
                        label: AppLocalizations.of(context)!.auditBodyQueryPath,
                        json: requestPayload,
                        emptyHint: AppLocalizations.of(
                          context,
                        )!.auditNotCapturedEnableSettingsAiTelemetry,
                      ),
                    ],
                  ),
                ),
                _AuditSectionCard(
                  icon: Icons.receipt_long_outlined,
                  collapsible: true,
                  initiallyExpanded: false,
                  title: AppLocalizations.of(context)!.auditRawAiResponse,
                  child: waitingForTelemetry && responseRaw == null
                      ? _auditShimmerBlock(lines: 4)
                      : _AuditJsonBlock(
                          label: AppLocalizations.of(
                            context,
                          )!.auditExpandRawResponse,
                          json: responseRaw,
                          emptyHint: AppLocalizations.of(
                            context,
                          )!.auditNotCapturedDebugDisabledOrResponse,
                        ),
                ),
                _AuditSectionCard(
                  icon: Icons.attach_file_outlined,
                  title: AppLocalizations.of(context)!.auditAttachments,
                  child: _AuditJsonBlock(
                    label: AppLocalizations.of(context)!.auditAttachmentList,
                    json: attachments,
                    emptyHint: AppLocalizations.of(context)!.auditNoAttachments,
                  ),
                ),
                _AuditSectionCard(
                  icon: Icons.data_object_rounded,
                  collapsible: true,
                  initiallyExpanded: false,
                  title: AppLocalizations.of(context)!.auditFullMetadata,
                  child: _AuditJsonBlock(
                    label: AppLocalizations.of(context)!.auditMessageMetadata,
                    json: metadata,
                    initiallyExpanded: true,
                  ),
                ),
                _AuditSectionCard(
                  icon: Icons.public_outlined,
                  collapsible: true,
                  initiallyExpanded: false,
                  title: AppLocalizations.of(context)!.auditSessionEnvironment,
                  child: _AuditJsonBlock(
                    label: AppLocalizations.of(
                      context,
                    )!.auditEnvironmentSnapshot,
                    json:
                        envSnapshot ??
                        _auditSafeMap(session.environment.toJson),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          OpenHandDialogActionButton.secondary(
            onPressed: () async {
              final payload = <String, Object?>{
                'message': message.toJson(),
                'session_id': session.id,
                'session_title': session.title,
                'environment': _auditSafeMap(session.environment.toJson),
              };
              await copyOpenHandTextToClipboard(
                logTag: 'home',
                context: context,
                text: _auditFormatJson(payload),
                successMessage: AppLocalizations.of(
                  context,
                )!.auditAuditSnapshotCopied,
                logAction: '复制审计快照',
              );
            },
            icon: Icons.copy_all_rounded,
            label: AppLocalizations.of(context)!.auditCopyAuditSnapshot,
          ),
          OpenHandDialogActionButton.primary(
            onPressed: () => Navigator.of(context).pop(),
            label: AppLocalizations.of(context)!.auditClose,
          ),
        ],
      ),
    );
  }
}

/// 会话元数据弹窗中的审计内容，提供标题、元数据和消息的审计操作。
class _SessionAuditContent extends StatefulWidget {
  const _SessionAuditContent({
    required this.session,
    required this.controller,
    required this.claudeStyle,
  });

  final AiSession session;
  final AiSessionController controller;
  final bool claudeStyle;

  @override
  State<_SessionAuditContent> createState() => _SessionAuditContentState();
}

class _SessionAuditContentState extends State<_SessionAuditContent> {
  late TextEditingController _titleController;
  late TextEditingController _metadataController;
  late FocusNode _titleFocusNode;
  late FocusNode _metadataFocusNode;
  String? _metadataError;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.session.title);
    _metadataController = TextEditingController(
      text: _auditFormatJson(widget.session.metadata),
    );
    _titleFocusNode = FocusNode();
    _metadataFocusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant _SessionAuditContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    syncTextControllerText(
      _titleController,
      widget.session.title,
      focusNode: _titleFocusNode,
    );
    syncTextControllerText(
      _metadataController,
      _auditFormatJson(widget.session.metadata),
      focusNode: _metadataFocusNode,
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _metadataController.dispose();
    _titleFocusNode.dispose();
    _metadataFocusNode.dispose();
    super.dispose();
  }

  AiSession get _liveSession =>
      widget.controller.sessionById(widget.session.id) ?? widget.session;

  Future<void> _saveTitle() async {
    final trimmed = _titleController.text.trim();
    if (trimmed.isEmpty || trimmed == _liveSession.title) return;
    setState(() => _busy = true);
    try {
      await widget.controller.renameSession(_liveSession.id, trimmed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveMetadata() async {
    setState(() {
      _metadataError = null;
      _busy = true;
    });
    try {
      final raw = _metadataController.text.trim();
      Map<String, Object?> parsed;
      if (raw.isEmpty) {
        parsed = const <String, Object?>{};
      } else {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) {
          throw const FormatException('Metadata root must be a JSON object.');
        }
        parsed = stringKeyedMapFromValue(decoded);
      }
      // 使用 null 清除已删除键；控制器会跳过未变化的字段。
      final currentKeys = _liveSession.metadata.keys.toSet();
      final nextKeys = parsed.keys.toSet();
      final payload = <String, Object?>{};
      for (final key in nextKeys) {
        payload[key] = parsed[key];
      }
      for (final key in currentKeys.difference(nextKeys)) {
        payload[key] = null;
      }
      await widget.controller.updateSessionMetadata(_liveSession.id, payload);
      if (!mounted) return;
      flashOpenHandSnack(
        context,
        AppLocalizations.of(context)!.auditSessionMetadataSaved,
        kind: OpenHandSnackKind.success,
      );
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() {
        _metadataError = AppLocalizations.of(
          context,
        )!.auditInvalidJsonErrorMessage(error.message);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _metadataError = AppLocalizations.of(
          context,
        )!.auditSaveFailedError(error);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteMessage(AiSessionMessage message) async {
    final loc = AppLocalizations.of(context)!;
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: loc.auditDeleteMessage,
      message: loc.auditDeleteThisMessageThisCannotBe,
      cancelLabel: loc.auditCancel,
      confirmLabel: loc.auditDelete,
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.controller.deleteMessages(<String>[
        message.id,
      ], sessionId: _liveSession.id);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final session = _liveSession;
    final statistics = session.statistics;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(height: 48),
        Row(
          children: [
            Icon(Icons.assignment_outlined, color: colorScheme.primary),
            kOpenHandHGap10,
            Expanded(
              child: Text(
                AppLocalizations.of(context)!.auditSessionAudit,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            OpenHandInlineRevealSwitcher(
              presentKey: const ValueKey<String>('audit-busy'),
              child: _busy
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      ),
                    )
                  : null,
            ),
          ],
        ),
        kOpenHandGap16,
        _AuditSectionCard(
          icon: Icons.info_outline_rounded,
          title: AppLocalizations.of(context)!.auditOverview,
          child: Column(
            children: [
              _AuditKvRow(
                label: AppLocalizations.of(context)!.auditSessionId,
                value: session.id,
                mono: true,
              ),
              _AuditKvRow(
                label: AppLocalizations.of(context)!.auditTemplate,
                value:
                    '${session.templateName} (${session.templateId}) · v${session.templateInternalVersion}',
              ),
              _AuditKvRow(
                label: AppLocalizations.of(context)!.auditCreatedAt,
                value: _auditFormatInstant(session.createdAt),
              ),
              _AuditKvRow(
                label: AppLocalizations.of(context)!.auditUpdatedAt,
                value: _auditFormatInstant(session.updatedAt),
              ),
              _AuditKvRow(
                label: AppLocalizations.of(context)!.auditMessages,
                value: '${statistics.totalMessageCount}',
              ),
              _AuditKvRow(
                label: AppLocalizations.of(context)!.auditTotalTokens,
                value: '${statistics.totalTokens ?? 0}',
              ),
              if ((statistics.cacheReadTokens ?? 0) > 0)
                _AuditKvRow(
                  label: AppLocalizations.of(context)!.tokenPopupCacheRead,
                  value: '${statistics.cacheReadTokens}',
                ),
              if ((statistics.cacheCreationTokens ?? 0) > 0)
                _AuditKvRow(
                  label: AppLocalizations.of(context)!.tokenPopupCacheWrite,
                  value: '${statistics.cacheCreationTokens}',
                ),
              if ((statistics.reasoningTokens ?? 0) > 0)
                _AuditKvRow(
                  label: AppLocalizations.of(context)!.tokenPopupReasoning,
                  value: '${statistics.reasoningTokens}',
                ),
              Builder(
                builder: (context) {
                  // 与 TopBar 胶囊 / 浮窗"Cache 命中率"走同一公式：
                  // 完整统计趋势点优先，当前消息窗口仅作兜底。
                  final trend = SessionCacheHitTrend.fromStatisticsOrSession(
                    session,
                    claudeStyle: widget.claudeStyle,
                  );
                  final ratio = trend
                      .displayData(
                        SessionCacheHitDisplayMode.excludeExpiredMisses,
                      )
                      .averageHitRatio;
                  if (ratio <= 0 && (statistics.cacheReadTokens ?? 0) <= 0) {
                    return const SizedBox.shrink();
                  }
                  return _AuditKvRow(
                    label: AppLocalizations.of(context)!.auditCacheHitRatio,
                    value: _auditFormatHitRatio(ratio),
                  );
                },
              ),
              _AuditKvRow(
                label: AppLocalizations.of(context)!.auditLastModel,
                value: _auditFormatOrDash(
                  session.lastUsedModelLabel ?? session.lastUsedModelId,
                ),
              ),
            ],
          ),
        ),
        _AuditSectionCard(
          icon: Icons.edit_note_rounded,
          title: AppLocalizations.of(context)!.auditTitleEditable,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _titleController,
                focusNode: _titleFocusNode,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.auditSessionTitle,
                ),
              ),
              kOpenHandGap10,
              Align(
                alignment: Alignment.centerRight,
                child: OpenHandDialogActionButton.primary(
                  onPressed: _busy ? null : _saveTitle,
                  icon: Icons.save_outlined,
                  label: AppLocalizations.of(context)!.auditSaveTitle,
                ),
              ),
            ],
          ),
        ),
        _AuditSectionCard(
          icon: Icons.data_object_rounded,
          title: AppLocalizations.of(context)!.auditSessionMetadataEditableJson,
          subtitle: AppLocalizations.of(
            context,
          )!.auditSaveWritesBackThroughTheSession,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _metadataController,
                focusNode: _metadataFocusNode,
                minLines: 6,
                maxLines: 16,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: kOpenHandMonospaceFontFamily,
                ),
                decoration: InputDecoration(
                  labelText: 'JSON',
                  errorText: _metadataError,
                ),
              ),
              kOpenHandGap10,
              Align(
                alignment: Alignment.centerRight,
                child: OpenHandDialogActionButton.primary(
                  onPressed: _busy ? null : _saveMetadata,
                  icon: Icons.save_outlined,
                  label: AppLocalizations.of(context)!.auditSaveMetadata,
                ),
              ),
            ],
          ),
        ),
        _AuditSectionCard(
          icon: Icons.route_outlined,
          collapsible: true,
          initiallyExpanded: false,
          title: AppLocalizations.of(
            context,
          )!.auditRuntimePromptMetadataReadOnly,
          subtitle: AppLocalizations.of(
            context,
          )!.auditUsefulForPromptConstructionTroubleshooti,
          child: _AuditJsonBlock(
            label: AppLocalizations.of(context)!.auditLastPromptMetadata,
            json: session.lastPromptMetadata,
            emptyHint: AppLocalizations.of(
              context,
            )!.auditNoRuntimePromptMetadataYet,
          ),
        ),
        _AuditSectionCard(
          icon: Icons.public_outlined,
          title: AppLocalizations.of(context)!.auditEnvironment,
          child: _AuditJsonBlock(
            label: AppLocalizations.of(context)!.auditEnvironmentSnapshot,
            json: _auditSafeMap(session.environment.toJson),
            initiallyExpanded: true,
          ),
        ),
        _AuditSectionCard(
          icon: Icons.history_rounded,
          title: AppLocalizations.of(context)!
              .auditRecentErrorsSessionRecenterrorsLength(
                session.recentErrors.length,
              ),
          child: _AuditJsonBlock(
            label: AppLocalizations.of(context)!.auditErrorList,
            json: session.recentErrors
                .map((error) => _auditSafeMap(error.toJson))
                .toList(growable: false),
            emptyHint: AppLocalizations.of(context)!.auditNoErrorsRecorded,
          ),
        ),
        _AuditSectionCard(
          icon: Icons.chat_bubble_outline_rounded,
          title: AppLocalizations.of(
            context,
          )!.auditMessagesSessionMessagesLength(session.messages.length),
          subtitle: AppLocalizations.of(context)!.auditTapARowToInspectA,
          child: Column(
            children: session.messages.isEmpty
                ? <Widget>[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        AppLocalizations.of(context)!.auditNoMessages,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ]
                : session.messages
                      .map(
                        (message) => _AuditMessageRow(
                          message: message,
                          onInspect: () async {
                            await _showMessageAuditDialog(
                              context,
                              message: message,
                              session: session,
                              controller: widget.controller,
                              claudeStyle: widget.claudeStyle,
                            );
                          },
                          onDelete: _busy
                              ? null
                              : () => _deleteMessage(message),
                        ),
                      )
                      .toList(growable: false),
          ),
        ),
      ],
    );
  }
}

class _AuditMessageRow extends StatelessWidget {
  const _AuditMessageRow({
    required this.message,
    required this.onInspect,
    required this.onDelete,
  });

  final AiSessionMessage message;
  final VoidCallback onInspect;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final snippet = message.content.trim();
    final preview = snippet.isEmpty
        ? '—'
        : clipTextByCodeUnits(snippet, 140, suffix: '…');
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: kOpenHandBorderRadius14,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: colorScheme.secondaryContainer,
              borderRadius: kOpenHandPillBorderRadius,
            ),
            child: Text(
              message.kind.storageValue,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSecondaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          kOpenHandHGap10,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.id,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontFamily: kOpenHandMonospaceFontFamily,
                  ),
                ),
                kOpenHandGap2,
                Text(
                  preview,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
                kOpenHandGap4,
                Text(
                  _auditFormatInstant(message.createdAt),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: AppLocalizations.of(context)!.auditAudit,
            icon: const Icon(Icons.fact_check_outlined, size: 20),
            onPressed: onInspect,
          ),
          kOpenHandHGap6,
          IconButton(
            tooltip: AppLocalizations.of(context)!.auditDelete,
            icon: Icon(
              Icons.delete_outline_rounded,
              size: 20,
              color: onDelete == null
                  ? colorScheme.onSurfaceVariant
                  : colorScheme.error,
            ),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

int? _auditFirstInt(Iterable<Object?> candidates) {
  for (final value in candidates) {
    final parsed = optionalIntFromValue(value);
    if (parsed != null) return parsed;
  }
  return null;
}

DateTime? _auditFirstDate(Iterable<Object?> candidates) {
  for (final value in candidates) {
    final parsed = dateTimeFromValue(value);
    if (parsed != null) return parsed;
  }
  return null;
}

String? _auditFirstString(Iterable<Object?> candidates) {
  for (final value in candidates) {
    if (value == null) continue;
    final text = '$value'.trim();
    if (text.isNotEmpty && text != 'null') return text;
  }
  return null;
}

bool _auditFirstBool(Iterable<Object?> candidates) {
  for (final value in candidates) {
    final parsed = optionalBoolFromValue(value);
    if (parsed != null) return parsed;
  }
  return false;
}

Map<String, Object?>? _auditFirstMap(Iterable<Object?> candidates) {
  for (final value in candidates) {
    if (value is Map<String, Object?>) return value;
    if (value is Map) return stringKeyedMapFromValue(value);
  }
  return null;
}

List<Object?>? _auditFirstList(Iterable<Object?> candidates) {
  for (final value in candidates) {
    if (value is List) return List<Object?>.from(value);
  }
  return null;
}

Object? _auditFirstAny(Iterable<Object?> candidates) {
  for (final value in candidates) {
    if (value != null) return value;
  }
  return null;
}

/// 安全读取模型序列化结果，失败时返回空映射。
Map<String, Object?> _auditSafeMap(Map<String, Object?> Function() builder) {
  try {
    return builder();
  } catch (_) {
    return const <String, Object?>{};
  }
}

/// 使用全局弹窗动效打开消息审计详情。
Future<void> _showMessageAuditDialog(
  BuildContext context, {
  required AiSessionMessage message,
  required AiSession session,
  required AiSessionController controller,
  required bool claudeStyle,
}) async {
  final relatedMessage = _auditRelatedTelemetryMessage(session, message);
  final deferredMessageIds = <String>{
    if (aiSessionMessageHasDeferredTelemetryMetadata(message.metadata))
      message.id,
    if (relatedMessage != null &&
        aiSessionMessageHasDeferredTelemetryMetadata(relatedMessage.metadata))
      relatedMessage.id,
  };
  final loadedMessages = await Future.wait(
    deferredMessageIds.map(
      (messageId) => controller.store.loadMessage(session.id, messageId),
    ),
  );
  final fullMessages = <String, AiSessionMessage>{
    for (final message in loadedMessages)
      if (message != null) message.id: message,
  };
  if (!context.mounted) return;
  final auditMessage = fullMessages[message.id] ?? message;
  final auditSession = fullMessages.isEmpty
      ? session
      : session.copyWith(
          messages: <AiSessionMessage>[
            for (final item in session.messages) fullMessages[item.id] ?? item,
          ],
        );
  return showAnimatedDialog<void>(
    context: context,
    builder: (dialogContext) => _MessageAuditDialog(
      message: auditMessage,
      session: auditSession,
      controller: controller,
      claudeStyle: claudeStyle,
    ),
  );
}

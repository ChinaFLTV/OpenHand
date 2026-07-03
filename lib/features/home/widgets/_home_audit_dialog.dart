part of '../openhand_home_page.dart';

/// Pretty-prints a JSON-ish value into a stable, human-readable string.
String _auditFormatJson(Object? value) {
  try {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(_auditSanitizeValue(value));
  } catch (_) {
    // Last-resort stringification keeps the dialog useful even for cyclic or
    // otherwise unencodable structures. This is intentionally permissive.
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
/// 与 [_TokenDial.cacheHitRatio] 同步的协议公式：
/// - Claude / Anthropic：prompt 不含 cache_read → 分母 = prompt + read。
/// - OpenAI 兼容系 / Gemini：prompt 已含 cache_read → 分母 = prompt。
/// 返回 null 表示无足够数据（usage 缺失 / 分母为 0）。
double? _auditMessageHitRatio({
  required int? promptTokens,
  required int? cacheReadTokens,
  required bool claudeStyle,
}) {
  final prompt = promptTokens ?? 0;
  final read = cacheReadTokens ?? 0;
  if (prompt <= 0 && read <= 0) return null;
  final ratio = computeCacheHitRatio(
    promptTokens: prompt,
    cacheReadTokens: read,
    claudeStyle: claudeStyle,
  );
  final denom = claudeStyle ? (prompt + read) : prompt;
  if (denom <= 0) return null;
  if (ratio.isNaN || ratio.isInfinite) return null;
  return ratio.clamp(0.0, 1.0).toDouble();
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
    final metadata = candidate.metadata;
    final hasTelemetry =
        candidate.modelId != null ||
        candidate.usage != null ||
        metadata.containsKey('started_at') ||
        metadata.containsKey('request_url') ||
        metadata.containsKey('request_payload') ||
        metadata.containsKey('response_raw') ||
        metadata.containsKey('error') ||
        metadata.containsKey('telemetry');
    if (hasTelemetry) {
      return candidate;
    }
  }
  return null;
}

/// Gemini-style greyscale sweep shimmer placeholder for audit fields that are
/// still being populated (e.g. while the AI response is streaming).
class _AuditShimmerPlaceholder extends StatefulWidget {
  const _AuditShimmerPlaceholder({this.width});

  final double? width;

  @override
  State<_AuditShimmerPlaceholder> createState() =>
      _AuditShimmerPlaceholderState();
}

class _AuditShimmerPlaceholderState extends State<_AuditShimmerPlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final baseColor = cs.surfaceContainerHighest;
    final highlightColor = cs.surfaceContainerLow;
    final animationsEnabled =
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context);
    if (!animationsEnabled) {
      _ctrl.stop();
      return _buildBar(baseColor, highlightColor, 0.5);
    }
    if (!_ctrl.isAnimating) {
      _ctrl.repeat();
    }
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return _buildBar(baseColor, highlightColor, _ctrl.value);
      },
    );
  }

  Widget _buildBar(Color baseColor, Color highlightColor, double progress) {
    return Container(
      width: widget.width ?? double.infinity,
      height: 14,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        gradient: LinearGradient(
          begin: Alignment(-1.0 + 2.0 * progress, 0),
          end: Alignment(-1.0 + 2.0 * progress + 1.0, 0),
          colors: [baseColor, highlightColor, baseColor],
        ),
      ),
    );
  }
}

/// A stack of shimmer bars that gives the impression of loading text content.
Widget _auditShimmerBlock({int lines = 3, double spacing = 8}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: List<Widget>.generate(lines, (i) {
      return Padding(
        padding: EdgeInsets.only(bottom: i < lines - 1 ? spacing : 0),
        child: _AuditShimmerPlaceholder(
          // Last line shorter to look more natural.
          width: i == lines - 1 ? 180 : null,
        ),
      );
    }),
  );
}

/// Smoothly animates dialog shell size changes caused by expanding/collapsing
/// large audit sections.
class _AuditDialogSizeAnimator extends StatelessWidget {
  const _AuditDialogSizeAnimator({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedSize(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 260),
        curve: Curves.easeInOutCubic,
        alignment: Alignment.topCenter,
        child: child,
      ),
    );
  }
}

/// Shared section card used by both the message-level and session-level audit
/// dialogs. Follows Material You Expressive surfaces and the active theme.
///
/// When [collapsible] is true the card renders a toggle chevron so the user
/// can expand/collapse the content with a smooth [AnimatedSize] transition.
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

  /// When true the body can be collapsed behind a chevron toggle.
  final bool collapsible;

  /// Only relevant when [collapsible] is true. Defaults to expanded.
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
        borderRadius: BorderRadius.circular(20),
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
            borderRadius: BorderRadius.circular(12),
            child: Row(
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, size: 18, color: colorScheme.primary),
                  const SizedBox(width: 8),
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
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 200),
                    curve: Curves.easeInOutCubic,
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
            const SizedBox(height: 4),
            Text(
              widget.subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          ClipRect(
            child: AnimatedSize(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              curve: Curves.easeInOutCubic,
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

/// Key-value row used by audit dialogs. Keys are right-aligned, values are
/// selectable so operators can copy individual fields quickly.
class _AuditKvRow extends StatelessWidget {
  const _AuditKvRow({
    required this.label,
    this.value,
    this.valueWidget,
    this.mono = false,
  }) : assert(value != null || valueWidget != null);

  final String label;
  final String? value;

  /// Optional custom widget shown instead of [value]. Used for shimmer
  /// placeholders during streaming.
  final Widget? valueWidget;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final valueStyle =
        (mono
                ? theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace')
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
          const SizedBox(width: 12),
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

/// A collapsible JSON block with copy-to-clipboard support.
/// Uses [AnimatedSize] + [ClipRect] for smooth expand/collapse transitions
/// consistent with the reasoning message card animation style.
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
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: _isEmpty
                ? null
                : () => setState(() => _expanded = !_expanded),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0.0,
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 200),
                    curve: Curves.easeInOutCubic,
                    child: Icon(
                      Icons.expand_more_rounded,
                      size: 18,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 6),
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
                        await Clipboard.setData(ClipboardData(text: rendered));
                        if (!context.mounted) return;
                        _showHomeSnackBar(
                          context,
                          SnackBar(
                            content: Text(
                              AppLocalizations.of(
                                context,
                              )!.auditCopiedToClipboard,
                            ),
                          ),
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
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 220),
                curve: Curves.easeInOutCubic,
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
                              fontFamily: 'monospace',
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

/// Message-level audit dialog. Shows raw response, parameters, timing,
/// error information and all other telemetry gleaned from the message model.
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
    final isZh = openHandIsChineseLocale(context);
    final size = MediaQuery.sizeOf(context);
    final maxWidth = size.width * 0.88;
    final maxHeight = size.height * 0.88;
    final metadata = Map<String, Object?>.from(message.metadata);
    final relatedMetadata = relatedMessage == null
        ? const <String, Object?>{}
        : Map<String, Object?>.from(relatedMessage.metadata);
    // Pull well-known telemetry shape if present.
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
        metadata['telemetry_in_flight'] == true ||
        relatedMetadata['telemetry_in_flight'] == true;
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
    // The composed prompt body that was actually sent to the AI. Stored on
    // user messages by the session controller when telemetry debug is on.
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        title: Row(
          children: [
            Icon(Icons.fact_check_outlined, color: colorScheme.primary),
            const SizedBox(width: 10),
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
                          valueWidget: const _AuditShimmerPlaceholder(
                            width: 200,
                          ),
                        )
                      else
                        _AuditKvRow(
                          label: AppLocalizations.of(context)!.auditEnded,
                          value: _auditFormatInstant(endedAt),
                        ),
                      if (waitingForTelemetry && durationMs == null)
                        _AuditKvRow(
                          label: AppLocalizations.of(context)!.auditDurationMs,
                          valueWidget: const _AuditShimmerPlaceholder(
                            width: 120,
                          ),
                        )
                      else
                        _AuditKvRow(
                          label: AppLocalizations.of(context)!.auditDurationMs,
                          value: durationMs == null ? '—' : '$durationMs',
                        ),
                      if (sendPreflightElapsedMs != null)
                        _AuditKvRow(
                          label: isZh ? '发送前耗时 (ms)' : 'Send Preflight (ms)',
                          value: '$sendPreflightElapsedMs',
                        ),
                      if (preRequestElapsedMs != null)
                        _AuditKvRow(
                          label: isZh ? '请求前耗时 (ms)' : 'Pre-request (ms)',
                          value: '$preRequestElapsedMs',
                        ),
                      if (sendPreflightTimings != null &&
                          sendPreflightTimings.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _AuditJsonBlock(
                          label: isZh ? '发送前阶段耗时' : 'Send Preflight Timings',
                          json: sendPreflightTimings,
                        ),
                      ],
                      if (preRequestTimings != null &&
                          preRequestTimings.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _AuditJsonBlock(
                          label: isZh ? '请求前阶段耗时' : 'Pre-request Timings',
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
                              ? const _AuditShimmerPlaceholder(width: 100)
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
                              ? const _AuditShimmerPlaceholder(width: 100)
                              : null,
                        ),
                        _AuditKvRow(
                          label: AppLocalizations.of(
                            context,
                          )!.auditCompletionTokens,
                          valueWidget: const _AuditShimmerPlaceholder(
                            width: 100,
                          ),
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
                          automaticProviderMissSuspected)
                        _AuditJsonBlock(
                          label: isZh ? '缓存诊断' : 'Cache Diagnostics',
                          initiallyExpanded: true,
                          json: <String, Object?>{
                            'idle_gap_seconds': cacheIdleGapSeconds,
                            'ttl_suspected': cacheTtlSuspected,
                            'prefix_drift_suspected': prefixDriftSuspected,
                            'automatic_provider_cache_miss_suspected':
                                automaticProviderMissSuspected,
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
                        fontFamily: 'monospace',
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
                          borderRadius: BorderRadius.circular(12),
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
                                  fontFamily: 'monospace',
                                ),
                              ),
                      ),
                      if (composedPromptText != null) ...[
                        const SizedBox(height: 10),
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
              await Clipboard.setData(
                ClipboardData(text: _auditFormatJson(payload)),
              );
              if (!context.mounted) return;
              _showHomeSnackBar(
                context,
                SnackBar(
                  content: Text(
                    AppLocalizations.of(context)!.auditAuditSnapshotCopied,
                  ),
                ),
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

/// Session-level audit dialog. Shows structured overview of the session and
/// exposes CRUD controls for the title, metadata JSON and individual messages.
class _SessionAuditDialog extends StatefulWidget {
  const _SessionAuditDialog({
    required this.session,
    required this.controller,
    required this.claudeStyle,
  });

  final AiSession session;
  final AiSessionController controller;
  final bool claudeStyle;

  @override
  State<_SessionAuditDialog> createState() => _SessionAuditDialogState();
}

class _SessionAuditDialogState extends State<_SessionAuditDialog> {
  late TextEditingController _titleController;
  late TextEditingController _metadataController;
  late FocusNode _titleFocusNode;
  late FocusNode _metadataFocusNode;
  bool _liveSyncScheduled = false;
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
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _titleController.dispose();
    _metadataController.dispose();
    _titleFocusNode.dispose();
    _metadataFocusNode.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    if (_liveSyncScheduled) {
      return;
    }
    _liveSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _liveSyncScheduled = false;
      if (!mounted) return;
      _syncLiveFieldsAndRebuild();
    });
  }

  void _syncLiveFieldsAndRebuild() {
    final session = _liveSession;
    if (!_titleFocusNode.hasFocus && _titleController.text != session.title) {
      _titleController.text = session.title;
    }
    final metadataJson = _auditFormatJson(session.metadata);
    if (!_metadataFocusNode.hasFocus &&
        _metadataController.text != metadataJson) {
      _metadataController.text = metadataJson;
    }
    // Force rebuild so newly persisted changes reflect instantly.
    setState(() {});
  }

  AiSession get _liveSession {
    final sessions = widget.controller.sessions;
    for (final item in sessions) {
      if (item.id == widget.session.id) return item;
    }
    return widget.session;
  }

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
        parsed = Map<String, Object?>.from(decoded);
      }
      // Build a diff payload that resets existing keys that were removed by
      // overlaying `null` onto them; updateSessionMetadata skips equal values
      // automatically.
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
      _showHomeSnackBar(
        context,
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.auditSessionMetadataSaved,
          ),
        ),
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
    if (confirmed != true) return;
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
    final size = MediaQuery.sizeOf(context);
    final maxWidth = size.width * 0.9;
    final maxHeight = size.height * 0.9;
    final session = _liveSession;
    final statistics = session.statistics;

    return _AuditDialogSizeAnimator(
      child: buildOpenHandAlertDialog(
        backgroundColor: colorScheme.surfaceContainerHighest,
        surfaceTintColor: Colors.transparent,
        titlePadding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
        contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        title: Row(
          children: [
            Icon(Icons.assignment_outlined, color: colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                AppLocalizations.of(context)!.auditSessionAudit,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
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
                          label: AppLocalizations.of(
                            context,
                          )!.tokenPopupCacheRead,
                          value: '${statistics.cacheReadTokens}',
                        ),
                      if ((statistics.cacheCreationTokens ?? 0) > 0)
                        _AuditKvRow(
                          label: AppLocalizations.of(
                            context,
                          )!.tokenPopupCacheWrite,
                          value: '${statistics.cacheCreationTokens}',
                        ),
                      if ((statistics.reasoningTokens ?? 0) > 0)
                        _AuditKvRow(
                          label: AppLocalizations.of(
                            context,
                          )!.tokenPopupReasoning,
                          value: '${statistics.reasoningTokens}',
                        ),
                      Builder(
                        builder: (context) {
                          // 与 TopBar 胶囊 / 浮窗"Cache 命中率"
                          // 走同一公式（[SessionCacheHitTrend] 排除首轮 + 排除
                          // 极端空闲 miss），避免审计页 / TopBar / 浮窗三方口径
                          // 错位。
                          final trend = SessionCacheHitTrend.fromSession(
                            session,
                            claudeStyle: widget.claudeStyle,
                          );
                          final ratio = trend
                              .displayData(
                                SessionCacheHitDisplayMode.excludeExtremeMisses,
                              )
                              .averageHitRatio;
                          if (ratio <= 0 &&
                              (statistics.cacheReadTokens ?? 0) <= 0) {
                            return const SizedBox.shrink();
                          }
                          return _AuditKvRow(
                            label: AppLocalizations.of(
                              context,
                            )!.auditCacheHitRatio,
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
                          labelText: AppLocalizations.of(
                            context,
                          )!.auditSessionTitle,
                        ),
                      ),
                      const SizedBox(height: 10),
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
                  title: AppLocalizations.of(
                    context,
                  )!.auditSessionMetadataEditableJson,
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
                          fontFamily: 'monospace',
                        ),
                        decoration: InputDecoration(
                          labelText: 'JSON',
                          errorText: _metadataError,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: OpenHandDialogActionButton.primary(
                          onPressed: _busy ? null : _saveMetadata,
                          icon: Icons.save_outlined,
                          label: AppLocalizations.of(
                            context,
                          )!.auditSaveMetadata,
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
                    label: AppLocalizations.of(
                      context,
                    )!.auditLastPromptMetadata,
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
                    label: AppLocalizations.of(
                      context,
                    )!.auditEnvironmentSnapshot,
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
                    emptyHint: AppLocalizations.of(
                      context,
                    )!.auditNoErrorsRecorded,
                  ),
                ),
                _AuditSectionCard(
                  icon: Icons.chat_bubble_outline_rounded,
                  title: AppLocalizations.of(context)!
                      .auditMessagesSessionMessagesLength(
                        session.messages.length,
                      ),
                  subtitle: AppLocalizations.of(
                    context,
                  )!.auditTapARowToInspectA,
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
            ),
          ),
        ),
        actions: [
          OpenHandDialogActionButton.primary(
            onPressed: () => Navigator.of(context).pop(),
            label: AppLocalizations.of(context)!.auditClose,
          ),
        ],
      ),
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
    final preview = snippet.length > 140
        ? '${snippet.substring(0, 140)}…'
        : (snippet.isEmpty ? '—' : snippet);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              message.kind.storageValue,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSecondaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.id,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  preview,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
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
          const SizedBox(width: 6),
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

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

int? _auditFirstInt(Iterable<Object?> candidates) {
  for (final value in candidates) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value.trim());
      if (parsed != null) return parsed;
    }
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

/// Safely invokes a toJson-like getter and falls back to an empty map on
/// failure. Keeps the audit dialog resilient against model-side serialization
/// regressions.
Map<String, Object?> _auditSafeMap(Map<String, Object?> Function() builder) {
  try {
    return builder();
  } catch (_) {
    return const <String, Object?>{};
  }
}

/// Opens the message-level audit dialog using the app's configured dialog
/// animations so entrance/exit behavior matches the rest of the product.
Future<void> _showMessageAuditDialog(
  BuildContext context, {
  required AiSessionMessage message,
  required AiSession session,
  required AiSessionController controller,
  required bool claudeStyle,
}) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (dialogContext) => _MessageAuditDialog(
      message: message,
      session: session,
      controller: controller,
      claudeStyle: claudeStyle,
    ),
  );
}

/// Opens the session-level audit dialog with full CRUD capability wired to
/// the provided [controller].
Future<void> _showSessionAuditDialog(
  BuildContext context, {
  required AiSession session,
  required AiSessionController controller,
  required bool claudeStyle,
}) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (dialogContext) => _SessionAuditDialog(
      session: session,
      controller: controller,
      claudeStyle: claudeStyle,
    ),
  );
}

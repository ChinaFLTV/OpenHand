part of '../openhand_home_page.dart';

const Color _kTrajectorySystemColor = Color(0xFF8A9099);
const Color _kTrajectoryUserColor = Color(0xFF5B8DEF);
const Color _kTrajectoryContextColor = Color(0xFF45A36B);
const Color _kTrajectoryAssistantColor = Color(0xFF9B72CF);
const Color _kTrajectoryToolColor = Color(0xFFE28A24);
const Color _kTrajectoryErrorColor = Color(0xFFE05A63);
const double _kTrajectoryRowHeight = 48;
const double _kTrajectoryTurnRailWidth = 68;
const double _kTrajectoryKindWidth = 112;
const double _kTrajectoryDetailsMinWidth = 320;
const double _kTrajectoryDetailsMaxWidth = 560;
const double _kTrajectoryDesktopBreakpoint = 820;
const double _kTrajectoryTableMinWidth = 760;
const double _kTrajectoryOlderLoadThreshold = 48;
const Duration _kTrajectoryRefreshDelay = Duration(milliseconds: 120);

enum _TrajectoryKind {
  system,
  user,
  context,
  compacted,
  assistant,
  tool,
  subtool,
}

class _TrajectoryRecord {
  const _TrajectoryRecord({
    required this.id,
    required this.index,
    required this.turn,
    required this.step,
    required this.requestNumber,
    required this.kind,
    required this.preview,
    required this.input,
    required this.output,
    required this.thinking,
    required this.startedAt,
    required this.durationMs,
    required this.running,
    required this.isError,
    required this.usage,
    required this.sourceMessageId,
    required this.resultMessageId,
    required this.callId,
    required this.toolName,
    required this.metadata,
  });

  final String id;
  final int index;
  final int turn;
  final int step;
  final int requestNumber;
  final _TrajectoryKind kind;
  final String preview;
  final String input;
  final String output;
  final String thinking;
  final DateTime? startedAt;
  final int? durationMs;
  final bool running;
  final bool isError;
  final AiTokenUsage? usage;
  final String? sourceMessageId;
  final String? resultMessageId;
  final String? callId;
  final String? toolName;
  final Map<String, Object?> metadata;

  bool get isInputLane =>
      kind == _TrajectoryKind.system ||
      kind == _TrajectoryKind.user ||
      kind == _TrajectoryKind.context;

  bool get isAssistantLane =>
      kind == _TrajectoryKind.assistant || kind == _TrajectoryKind.compacted;

  int get lane => isInputLane ? 0 : (isAssistantLane ? 1 : 2);

  String get searchableText => <String>[
    preview,
    input,
    output,
    thinking,
    toolName ?? '',
    callId ?? '',
  ].join('\n').toLowerCase();
}

class _TrajectorySnapshot {
  const _TrajectorySnapshot({
    required this.records,
    required this.turnIds,
    required this.collapsibleTurnIds,
    required this.assistantCallAnchors,
  });

  final List<_TrajectoryRecord> records;
  final Set<int> turnIds;
  final Set<int> collapsibleTurnIds;
  final Set<String> assistantCallAnchors;

  static _TrajectorySnapshot fromSession(AiSession session) {
    final messages = session.messages
        .where((message) => !message.isDeleted)
        .toList(growable: false);
    final resultByCallId = <String, AiSessionMessage>{};
    final pairedResultIds = <String>{};
    for (final message in messages) {
      if (!message.kind.isToolResultKind) continue;
      final callId = '${message.metadata[aiSessionMessageToolCallIdMetadataKey] ?? ''}'.trim();
      if (callId.isNotEmpty) resultByCallId[callId] = message;
    }

    final records = <_TrajectoryRecord>[];
    var recordIndex = 0;
    var turn = 0;
    var step = 0;
    var requestNumber = 0;
    var nextAssistantStartsStep = true;
    AiSessionMessage? firstRequestMessage;
    for (final message in messages) {
      if (message.carriesRequestTelemetry ||
          aiSessionMessageHasDeferredTelemetryMetadata(message.metadata)) {
        firstRequestMessage ??= message;
      }
    }
    records.add(
      _TrajectoryRecord(
        id: 'system-initial',
        index: ++recordIndex,
        turn: 0,
        step: 0,
        requestNumber: 0,
        kind: _TrajectoryKind.system,
        preview: 'Initial System Prompt',
        input: '',
        output: '',
        thinking: '',
        startedAt: session.createdAt,
        durationMs: null,
        running: false,
        isError: false,
        usage: null,
        sourceMessageId: firstRequestMessage?.id,
        resultMessageId: null,
        callId: null,
        toolName: null,
        metadata: firstRequestMessage?.metadata ?? const <String, Object?>{},
      ),
    );

    for (final message in messages) {
      if (pairedResultIds.contains(message.id)) continue;
      final metadata = message.metadata;
      final callId = '${metadata[aiSessionMessageToolCallIdMetadataKey] ?? ''}'.trim();
      switch (message.kind) {
        case AiSessionMessageKind.user:
          if (message.isGoalEvaluationMessage) {
            records.add(
              _trajectoryRecordFromMessage(
                message,
                index: ++recordIndex,
                turn: math.max(1, turn),
                step: step,
                requestNumber: requestNumber,
                kind: _TrajectoryKind.context,
              ),
            );
            break;
          }
          turn += 1;
          step = 0;
          nextAssistantStartsStep = true;
          records.add(
            _trajectoryRecordFromMessage(
              message,
              index: ++recordIndex,
              turn: turn,
              step: 0,
              requestNumber: requestNumber,
              kind: _TrajectoryKind.user,
            ),
          );
        case AiSessionMessageKind.reasoning:
        case AiSessionMessageKind.assistant:
          if (turn == 0) turn = 1;
          if (nextAssistantStartsStep || step == 0) {
            step += 1;
            requestNumber += 1;
            nextAssistantStartsStep = false;
          }
          records.add(
            _trajectoryRecordFromMessage(
              message,
              index: ++recordIndex,
              turn: turn,
              step: step,
              requestNumber: requestNumber,
              kind: _TrajectoryKind.assistant,
            ),
          );
        case AiSessionMessageKind.toolCall:
          if (turn == 0) turn = 1;
          if (step == 0) {
            step = 1;
            requestNumber += 1;
          }
          final result = callId.isEmpty ? null : resultByCallId[callId];
          if (result != null) pairedResultIds.add(result.id);
          records.add(
            _trajectoryToolRecord(
              message,
              result,
              index: ++recordIndex,
              turn: turn,
              step: step,
              requestNumber: requestNumber,
            ),
          );
          nextAssistantStartsStep = true;
        case AiSessionMessageKind.tool:
        case AiSessionMessageKind.mcp:
        case AiSessionMessageKind.skill:
        case AiSessionMessageKind.hook:
          if (turn == 0) turn = 1;
          records.add(
            _trajectoryToolResultRecord(
              message,
              index: ++recordIndex,
              turn: turn,
              step: math.max(1, step),
              requestNumber: requestNumber,
            ),
          );
          nextAssistantStartsStep = true;
        case AiSessionMessageKind.compressionPoint:
          records.add(
            _trajectoryRecordFromMessage(
              message,
              index: ++recordIndex,
              turn: turn,
              step: step,
              requestNumber: requestNumber,
              kind: _TrajectoryKind.compacted,
            ),
          );
        case AiSessionMessageKind.status:
        case AiSessionMessageKind.selfLearning:
        case AiSessionMessageKind.fileMutationSummary:
          final preview = _trajectoryMessagePreview(message);
          if (preview.isEmpty) break;
          records.add(
            _trajectoryRecordFromMessage(
              message,
              index: ++recordIndex,
              turn: math.max(1, turn),
              step: step,
              requestNumber: requestNumber,
              kind: _TrajectoryKind.context,
            ),
          );
      }
    }

    final turnIds = <int>{
      for (final record in records)
        if (record.turn > 0) record.turn,
    };
    final recordsPerTurn = <int, int>{};
    for (final record in records) {
      if (record.turn <= 0) continue;
      recordsPerTurn.update(
        record.turn,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    final collapsibleTurnIds = <int>{
      for (final entry in recordsPerTurn.entries)
        if (entry.value > 1) entry.key,
    };
    final assistantCallAnchors = <String>{};
    for (var index = 0; index < records.length; index += 1) {
      final record = records[index];
      if (record.kind != _TrajectoryKind.assistant) continue;
      for (var next = index + 1; next < records.length; next += 1) {
        final candidate = records[next];
        if (candidate.turn != record.turn || candidate.step != record.step) {
          break;
        }
        if (candidate.kind == _TrajectoryKind.tool ||
            candidate.kind == _TrajectoryKind.subtool) {
          assistantCallAnchors.add(record.id);
          break;
        }
      }
    }
    return _TrajectorySnapshot(
      records: List<_TrajectoryRecord>.unmodifiable(records),
      turnIds: Set<int>.unmodifiable(turnIds),
      collapsibleTurnIds: Set<int>.unmodifiable(collapsibleTurnIds),
      assistantCallAnchors: Set<String>.unmodifiable(assistantCallAnchors),
    );
  }
}

_TrajectoryRecord _trajectoryRecordFromMessage(
  AiSessionMessage message, {
  required int index,
  required int turn,
  required int step,
  required int requestNumber,
  required _TrajectoryKind kind,
}) {
  final metadata = message.metadata;
  final timing = _trajectoryTiming(message, kind);
  final content = message.content.trim();
  return _TrajectoryRecord(
    id: 'message-${message.id}',
    index: index,
    turn: turn,
    step: step,
    requestNumber: requestNumber,
    kind: kind,
    preview: _trajectoryMessagePreview(message),
    input: kind == _TrajectoryKind.user || kind == _TrajectoryKind.context
        ? content
        : '',
    output:
        kind == _TrajectoryKind.assistant || kind == _TrajectoryKind.compacted
        ? content
        : '',
    thinking: message.kind == AiSessionMessageKind.reasoning ? content : '',
    startedAt: timing.$1,
    durationMs: timing.$2,
    running:
        metadata[aiSessionMessageMetadataStreamingKey] == true ||
        metadata[aiSessionMessageTelemetryInFlightMetadataKey] == true,
    isError: '${metadata['error'] ?? ''}'.trim().isNotEmpty,
    usage: message.usage,
    sourceMessageId: message.id,
    resultMessageId: null,
    callId: null,
    toolName: null,
    metadata: metadata,
  );
}

_TrajectoryRecord _trajectoryToolRecord(
  AiSessionMessage call,
  AiSessionMessage? result, {
  required int index,
  required int turn,
  required int step,
  required int requestNumber,
}) {
  final metadata = call.metadata;
  final callId = '${metadata[aiSessionMessageToolCallIdMetadataKey] ?? ''}'.trim();
  final toolName = '${metadata['tool_name'] ?? ''}'.trim();
  final arguments = '${metadata['tool_arguments'] ?? call.content}'.trim();
  final output = (result?.content ?? _trajectoryToolOutput(metadata)).trim();
  final timing = _trajectoryTiming(call, _TrajectoryKind.tool);
  final status = '${metadata['tool_execution_status'] ?? ''}'
      .trim()
      .toLowerCase();
  final error = const <String>{
    'failed',
    'cancelled',
    'denied',
    'rejected',
    'timed_out',
    'invalid_arguments',
  }.contains(status);
  return _TrajectoryRecord(
    id: callId.isEmpty ? 'message-${call.id}' : 'tool-$callId',
    index: index,
    turn: turn,
    step: step,
    requestNumber: requestNumber,
    kind: _TrajectoryKind.tool,
    preview: _trajectoryToolPreview(toolName, arguments, output),
    input: arguments,
    output: output,
    thinking: '',
    startedAt: timing.$1,
    durationMs: timing.$2,
    running:
        status == 'running' ||
        metadata['tool_arguments_streaming'] == true ||
        (result == null && output.isEmpty && status.isEmpty),
    isError: error || '${result?.metadata['error'] ?? ''}'.trim().isNotEmpty,
    usage: call.usage,
    sourceMessageId: call.id,
    resultMessageId: result?.id,
    callId: callId.isEmpty ? null : callId,
    toolName: toolName.isEmpty ? null : toolName,
    metadata: metadata,
  );
}

_TrajectoryRecord _trajectoryToolResultRecord(
  AiSessionMessage message, {
  required int index,
  required int turn,
  required int step,
  required int requestNumber,
}) {
  final metadata = message.metadata;
  final callId = '${metadata[aiSessionMessageToolCallIdMetadataKey] ?? ''}'.trim();
  final toolName = '${metadata['tool_name'] ?? message.kind.storageValue}'
      .trim();
  final status = '${metadata['tool_execution_status'] ?? ''}'
      .trim()
      .toLowerCase();
  return _TrajectoryRecord(
    id: callId.isEmpty ? 'result-${message.id}' : 'tool-result-$callId',
    index: index,
    turn: turn,
    step: step,
    requestNumber: requestNumber,
    kind: _TrajectoryKind.tool,
    preview: _trajectoryToolPreview(toolName, '', message.content),
    input: '',
    output: message.content,
    thinking: '',
    startedAt: message.createdAt,
    durationMs: _trajectoryMetadataInt(metadata, const <String>[
      'tool_execution_elapsed_ms',
      'tool_execution_duration_ms',
      'duration_ms',
    ]),
    running: status == 'running',
    isError: const <String>{
      'failed',
      'cancelled',
      'timed_out',
    }.contains(status),
    usage: message.usage,
    sourceMessageId: message.id,
    resultMessageId: null,
    callId: callId.isEmpty ? null : callId,
    toolName: toolName.isEmpty ? null : toolName,
    metadata: metadata,
  );
}

(DateTime?, int?) _trajectoryTiming(
  AiSessionMessage message,
  _TrajectoryKind kind,
) {
  final metadata = message.metadata;
  final startKeys = switch (kind) {
    _TrajectoryKind.tool || _TrajectoryKind.subtool => const <String>[
      'tool_execution_started_at',
      'started_at',
    ],
    _TrajectoryKind.assistant =>
      message.kind == AiSessionMessageKind.reasoning
          ? const <String>[
              aiSessionMessageReasoningStartedAtKey,
              'started_at',
              'request_started_at',
            ]
          : const <String>['request_started_at', 'started_at'],
    _ => const <String>['started_at'],
  };
  final endKeys = switch (kind) {
    _TrajectoryKind.tool || _TrajectoryKind.subtool => const <String>[
      'tool_execution_finished_at',
      'ended_at',
    ],
    _TrajectoryKind.assistant =>
      message.kind == AiSessionMessageKind.reasoning
          ? const <String>[aiSessionMessageReasoningEndedAtKey, 'ended_at']
          : const <String>['ended_at'],
    _ => const <String>['ended_at'],
  };
  final durationKeys = switch (kind) {
    _TrajectoryKind.tool || _TrajectoryKind.subtool => const <String>[
      'tool_execution_elapsed_ms',
      'tool_execution_duration_ms',
      'duration_ms',
    ],
    _TrajectoryKind.assistant =>
      message.kind == AiSessionMessageKind.reasoning
          ? const <String>[aiSessionMessageReasoningElapsedMsKey, 'duration_ms']
          : const <String>['duration_ms'],
    _ => const <String>['duration_ms'],
  };
  final startedAt = _trajectoryMetadataDate(metadata, startKeys);
  final endedAt = _trajectoryMetadataDate(metadata, endKeys);
  final recordedDuration = _trajectoryMetadataInt(metadata, durationKeys);
  final duration =
      recordedDuration ??
      (startedAt != null && endedAt != null
          ? math.max(0, endedAt.difference(startedAt).inMilliseconds)
          : null);
  return (startedAt ?? message.createdAt, duration);
}

DateTime? _trajectoryMetadataDate(
  Map<String, Object?> metadata,
  List<String> keys,
) {
  for (final key in keys) {
    final value = metadata[key];
    if (value == null) continue;
    final parsed = utcDateTimeFromValue(value);
    if (parsed != null) return parsed;
  }
  return null;
}

int? _trajectoryMetadataInt(Map<String, Object?> metadata, List<String> keys) {
  for (final key in keys) {
    final parsed = optionalNonNegativeIntegralIntFromValue(metadata[key]);
    if (parsed != null) return parsed;
  }
  return null;
}

String _trajectoryToolOutput(Map<String, Object?> metadata) {
  for (final key in const <String>[
    'tool_execution_result',
    'result_text',
    'tool_execution_stdout',
    'tool_execution_stderr',
  ]) {
    final text = '${metadata[key] ?? ''}'.trim();
    if (text.isNotEmpty) return text;
  }
  return '';
}

String _trajectoryMessagePreview(AiSessionMessage message) {
  final content = collapseInlineWhitespace(message.content);
  if (content.isNotEmpty) return clipTextWithEllipsis(content, 520);
  if (message.kind == AiSessionMessageKind.fileMutationSummary) {
    return 'File mutation summary';
  }
  return '';
}

String _trajectoryToolPreview(
  String toolName,
  String arguments,
  String output,
) {
  final name = toolName.isEmpty ? 'tool' : toolName;
  final inputPreview = clipTextWithEllipsis(
    collapseInlineWhitespace(arguments),
    260,
  );
  final outputPreview = clipTextWithEllipsis(
    collapseInlineWhitespace(output),
    260,
  );
  if (inputPreview.isEmpty && outputPreview.isEmpty) return name;
  if (outputPreview.isEmpty) return '$name  $inputPreview';
  if (inputPreview.isEmpty) return '$name  →  $outputPreview';
  return '$name  $inputPreview  →  $outputPreview';
}

class _TrajectoryRange {
  const _TrajectoryRange(this.start, this.end);

  final double start;
  final double end;
}

class _TrajectorySpan {
  const _TrajectorySpan({
    required this.record,
    required this.start,
    required this.end,
  });

  final _TrajectoryRecord record;
  final double start;
  final double end;
}

class _TrajectoryProjection {
  const _TrajectoryProjection({
    required this.start,
    required this.end,
    required this.spans,
    required this.turnBoundaries,
  });

  final double start;
  final double end;
  final List<_TrajectorySpan> spans;
  final Map<int, double> turnBoundaries;
}

_TrajectoryProjection _trajectoryProjection(
  List<_TrajectoryRecord> records, {
  required bool actualDuration,
}) {
  if (!actualDuration) {
    final spans = <_TrajectorySpan>[];
    final boundaries = <int, double>{};
    for (final record in records) {
      boundaries.putIfAbsent(record.turn, () => spans.length.toDouble());
      final start = spans.length.toDouble();
      spans.add(_TrajectorySpan(record: record, start: start, end: start + 1));
    }
    return _TrajectoryProjection(
      start: 0,
      end: math.max(1, spans.length).toDouble(),
      spans: spans,
      turnBoundaries: boundaries,
    );
  }
  final timed =
      records
          .where((record) => record.startedAt != null)
          .toList(growable: false)
        ..sort((left, right) {
          final byStart = left.startedAt!.compareTo(right.startedAt!);
          return byStart == 0 ? left.index.compareTo(right.index) : byStart;
        });
  if (timed.isEmpty) {
    return _trajectoryProjection(records, actualDuration: false);
  }
  final epoch = timed.first.startedAt!.millisecondsSinceEpoch.toDouble();
  var removedIdle = 0.0;
  double? coveredUntil;
  final spans = <_TrajectorySpan>[];
  final boundaries = <int, double>{};
  for (final record in timed) {
    final rawStart = record.startedAt!.millisecondsSinceEpoch - epoch;
    final rawEnd = rawStart + (record.durationMs ?? 0);
    if (coveredUntil != null && rawStart > coveredUntil) {
      removedIdle += rawStart - coveredUntil;
    }
    final start = rawStart - removedIdle;
    final end = math.max(start + 1, rawEnd - removedIdle);
    boundaries.putIfAbsent(record.turn, () => start);
    spans.add(_TrajectorySpan(record: record, start: start, end: end));
    coveredUntil = coveredUntil == null
        ? rawEnd.toDouble()
        : math.max(coveredUntil, rawEnd.toDouble());
  }
  final end = spans.fold<double>(1, (value, span) => math.max(value, span.end));
  return _TrajectoryProjection(
    start: 0,
    end: end,
    spans: spans,
    turnBoundaries: boundaries,
  );
}

extension on _OpenHandHomePageState {
  void _showTrajectoryForSession(AiSession session) {
    final controller = context.read<AiSessionController>();
    unawaited(
      showAnimatedDialog<void>(
        context: context,
        builder: (_) =>
            _TrajectoryDialog(controller: controller, initialSession: session),
      ),
    );
  }
}

class _TrajectoryLedgerRow {
  const _TrajectoryLedgerRow.record(this.record)
    : summary = null,
      summaryKind = null;

  const _TrajectoryLedgerRow.summary({
    required this.record,
    required this.summary,
    required this.summaryKind,
  });

  final _TrajectoryRecord record;
  final String? summary;
  final String? summaryKind;
}

class _TrajectoryDialog extends StatefulWidget {
  const _TrajectoryDialog({
    required this.controller,
    required this.initialSession,
  });

  final AiSessionController controller;
  final AiSession initialSession;

  @override
  State<_TrajectoryDialog> createState() => _TrajectoryDialogState();
}

class _TrajectoryDialogState extends State<_TrajectoryDialog> {
  late AiSession _session;
  late _TrajectorySnapshot _snapshot;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _ledgerScrollController = ScrollController();
  final ScrollController _ledgerHorizontalController = ScrollController();
  final Set<int> _collapsedTurns = <int>{};
  final Set<String> _collapsedCalls = <String>{};
  late final OpenHandDebouncer _refreshDebouncer = OpenHandDebouncer(
    delay: _kTrajectoryRefreshDelay,
  );
  bool _loadingInitial = true;
  bool _loadingOlder = false;
  bool _suppressControllerSync = false;
  bool _actualDuration = false;
  String? _loadError;
  String _searchQuery = '';
  String? _selectedRecordId;
  String _activeDetailTab = 'summary';
  Map<String, Object?> _selectedMetadata = const <String, Object?>{};
  bool _selectedMetadataLoading = false;
  int _metadataLoadGeneration = 0;
  double _detailsWidth = 390;
  _TrajectoryRange? _timelineRange;

  @override
  void initState() {
    super.initState();
    _session = widget.initialSession;
    _snapshot = _TrajectorySnapshot.fromSession(_session);
    _searchController.addListener(_onSearchChanged);
    _ledgerScrollController.addListener(_onLedgerScroll);
    widget.controller.addListener(_onControllerChanged);
    unawaited(_loadInitialWindow());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _refreshDebouncer.dispose();
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    _ledgerScrollController
      ..removeListener(_onLedgerScroll)
      ..dispose();
    _ledgerHorizontalController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialWindow() async {
    final loaded = await widget.controller.ensureSessionMessageWindowHydrated(
      _session.id,
    );
    if (!mounted) return;
    final effective = loaded ?? widget.controller.sessionById(_session.id);
    setState(() {
      _loadingInitial = false;
      if (effective == null) {
        _loadError = openHandLocalizedText(
          context,
          zh: '无法读取该线程的轨迹。',
          en: 'Unable to load this thread trajectory.',
        );
        return;
      }
      _loadError = null;
      _replaceSession(effective);
    });
    _scrollLedgerToTail();
  }

  void _onControllerChanged() {
    if (!mounted || _suppressControllerSync) return;
    _refreshDebouncer.schedule(() {
      if (!mounted) return;
      final live = widget.controller.sessionById(_session.id);
      if (live == null) return;
      if (identical(live.messages, _session.messages) &&
          live.messageLoadState == _session.messageLoadState &&
          live.messageWindowStartIndex == _session.messageWindowStartIndex) {
        return;
      }
      final followTail =
          !_ledgerScrollController.hasClients ||
          _ledgerScrollController.position.maxScrollExtent -
                  _ledgerScrollController.offset <=
              2;
      setState(() => _replaceSession(live));
      if (followTail) _scrollLedgerToTail();
    });
  }

  void _replaceSession(AiSession session) {
    _session = session;
    _snapshot = _TrajectorySnapshot.fromSession(session);
    _collapsedTurns.removeWhere((turn) => !_snapshot.turnIds.contains(turn));
    _collapsedCalls.removeWhere(
      (id) => !_snapshot.assistantCallAnchors.contains(id),
    );
    final selectedId = _selectedRecordId;
    if (selectedId != null &&
        !_snapshot.records.any((record) => record.id == selectedId)) {
      _selectedRecordId = null;
      _selectedMetadata = const <String, Object?>{};
    }
  }

  void _onSearchChanged() {
    final query = collapseInlineWhitespace(
      _searchController.text,
    ).toLowerCase();
    if (query == _searchQuery) return;
    setState(() {
      _searchQuery = query;
      _timelineRange = null;
    });
  }

  void _onLedgerScroll() {
    if (!_ledgerScrollController.hasClients ||
        _ledgerScrollController.offset > _kTrajectoryOlderLoadThreshold ||
        !_session.hasMoreHistoricalMessages ||
        _loadingOlder) {
      return;
    }
    unawaited(_loadOlder());
  }

  Future<void> _loadOlder() async {
    if (_loadingOlder || !_session.hasMoreHistoricalMessages) return;
    final oldMax = _ledgerScrollController.hasClients
        ? _ledgerScrollController.position.maxScrollExtent
        : 0.0;
    _suppressControllerSync = true;
    setState(() => _loadingOlder = true);
    final loaded = await widget.controller.loadOlderSessionMessages(
      _session.id,
    );
    _suppressControllerSync = false;
    if (!mounted) return;
    setState(() {
      _loadingOlder = false;
      if (loaded != null) _replaceSession(loaded);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_ledgerScrollController.hasClients) return;
      final addedExtent =
          _ledgerScrollController.position.maxScrollExtent - oldMax;
      if (addedExtent > 0) {
        _ledgerScrollController.jumpTo(
          (_ledgerScrollController.offset + addedExtent).clamp(
            0,
            _ledgerScrollController.position.maxScrollExtent,
          ),
        );
      }
    });
  }

  void _scrollLedgerToTail() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_ledgerScrollController.hasClients) return;
      _ledgerScrollController.jumpTo(
        _ledgerScrollController.position.maxScrollExtent,
      );
    });
  }

  Set<String>? get _searchMatches {
    if (_searchQuery.isEmpty) return null;
    return <String>{
      for (final record in _snapshot.records)
        if (record.searchableText.contains(_searchQuery)) record.id,
    };
  }

  Set<String>? get _timelineMatches {
    final range = _timelineRange;
    if (range == null) return null;
    final projection = _trajectoryProjection(
      _snapshot.records,
      actualDuration: _actualDuration,
    );
    return <String>{
      for (final span in projection.spans)
        if (span.start <= range.end && span.end >= range.start) span.record.id,
    };
  }

  Set<int> get _collapsibleTurns => _snapshot.collapsibleTurnIds;

  List<_TrajectoryLedgerRow> get _ledgerRows {
    final searchMatches = _searchMatches;
    final timelineMatches = _timelineMatches;
    final filtered = _snapshot.records
        .where((record) {
          if (searchMatches != null && !searchMatches.contains(record.id)) {
            return false;
          }
          if (timelineMatches != null && !timelineMatches.contains(record.id)) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
    final recordsByTurn = <int, List<_TrajectoryRecord>>{};
    for (final record in filtered) {
      if (record.turn <= 0) continue;
      recordsByTurn
          .putIfAbsent(record.turn, () => <_TrajectoryRecord>[])
          .add(record);
    }
    final rows = <_TrajectoryLedgerRow>[];
    for (var index = 0; index < filtered.length; index += 1) {
      final record = filtered[index];
      if (record.turn > 0 && _collapsedTurns.contains(record.turn)) {
        final turnRecords =
            recordsByTurn[record.turn] ?? const <_TrajectoryRecord>[];
        if (record.id != turnRecords.first.id) continue;
        rows.add(_TrajectoryLedgerRow.record(record));
        if (turnRecords.length > 1) {
          final steps = turnRecords
              .map((item) => item.step)
              .where((item) => item > 0)
              .toSet();
          final calls = turnRecords
              .where((item) => item.kind == _TrajectoryKind.tool)
              .length;
          rows.add(
            _TrajectoryLedgerRow.summary(
              record: record,
              summary:
                  '${steps.length} ${steps.length == 1 ? 'step' : 'steps'} · '
                  '$calls tool ${calls == 1 ? 'call' : 'calls'}',
              summaryKind: 'turn',
            ),
          );
        }
        index += turnRecords.length - 1;
        continue;
      }
      rows.add(_TrajectoryLedgerRow.record(record));
      if (!_collapsedCalls.contains(record.id)) continue;
      final calls = <_TrajectoryRecord>[];
      var next = index + 1;
      while (next < filtered.length) {
        final candidate = filtered[next];
        if (candidate.turn != record.turn || candidate.step != record.step) {
          break;
        }
        if (candidate.kind != _TrajectoryKind.tool &&
            candidate.kind != _TrajectoryKind.subtool) {
          break;
        }
        calls.add(candidate);
        next += 1;
      }
      if (calls.isEmpty) continue;
      final names = calls
          .map((call) => call.toolName ?? 'tool')
          .toSet()
          .join(', ');
      rows.add(
        _TrajectoryLedgerRow.summary(
          record: record,
          summary:
              '${calls.length} tool ${calls.length == 1 ? 'call' : 'calls'} · $names',
          summaryKind: 'calls',
        ),
      );
      index += calls.length;
    }
    return rows;
  }

  _TrajectoryRecord? get _selectedRecord {
    final id = _selectedRecordId;
    if (id == null) return null;
    for (final record in _snapshot.records) {
      if (record.id == id) return record;
    }
    return null;
  }

  void _selectRecord(_TrajectoryRecord record) {
    if (_selectedRecordId == record.id) return;
    setState(() {
      _selectedRecordId = record.id;
      _selectedMetadata = record.metadata;
      _selectedMetadataLoading = false;
      _activeDetailTab = _trajectoryDetailTabs(record).first.$1;
    });
    final messageId = record.sourceMessageId;
    if (messageId == null) return;
    final generation = ++_metadataLoadGeneration;
    setState(() => _selectedMetadataLoading = true);
    widget.controller
        .loadFullSessionMessageMetadata(_session.id, messageId)
        .then((metadata) {
          if (!mounted ||
              generation != _metadataLoadGeneration ||
              _selectedRecordId != record.id) {
            return;
          }
          setState(() {
            _selectedMetadata = metadata;
            _selectedMetadataLoading = false;
          });
        });
  }

  void _selectRecordFromTimeline(_TrajectoryRecord record) {
    _selectRecord(record);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_ledgerScrollController.hasClients) return;
      final rows = _ledgerRows;
      final index = rows.indexWhere((row) => row.record.id == record.id);
      if (index < 0) return;
      final leading = _session.hasMoreHistoricalMessages ? 1 : 0;
      final target =
          ((index + leading) * _kTrajectoryRowHeight -
                  _ledgerScrollController.position.viewportDimension * 0.42)
              .clamp(0.0, _ledgerScrollController.position.maxScrollExtent);
      unawaited(
        _ledgerScrollController.animateTo(
          target,
          duration: openHandMotionDuration(context, kOpenHandMotion220),
          curve: Curves.easeOutCubic,
        ),
      );
    });
  }

  void _closeDetails() {
    _metadataLoadGeneration += 1;
    setState(() {
      _selectedRecordId = null;
      _selectedMetadataLoading = false;
      _selectedMetadata = const <String, Object?>{};
    });
  }

  void _toggleAllTurns() {
    final collapsible = _collapsibleTurns;
    final allCollapsed =
        collapsible.isNotEmpty && collapsible.every(_collapsedTurns.contains);
    setState(() {
      if (allCollapsed) {
        _collapsedTurns.removeAll(collapsible);
      } else {
        _collapsedTurns.addAll(collapsible);
      }
    });
  }

  void _toggleAllCalls() {
    final collapsible = _snapshot.assistantCallAnchors;
    final allCollapsed =
        collapsible.isNotEmpty && collapsible.every(_collapsedCalls.contains);
    setState(() {
      if (allCollapsed) {
        _collapsedCalls.removeAll(collapsible);
      } else {
        _collapsedCalls.addAll(collapsible);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final viewport = MediaQuery.sizeOf(context);
    final width = resolveOpenHandResponsiveDialogExtent(
      viewportExtent: viewport.width,
      maxExtent: kOpenHandDialogWidthFull,
      minAvailableExtent: 320,
      viewportMargin: 28,
    );
    final height = resolveOpenHandResponsiveDialogExtent(
      viewportExtent: viewport.height,
      maxExtent: kOpenHandDialogHeightFull,
      minAvailableExtent: 420,
      viewportMargin: 28,
    );
    final radius = BorderRadius.circular(18);
    return buildOpenHandDialog(
      width: width,
      height: height,
      insetPadding: const EdgeInsets.all(14),
      backgroundColor: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Column(
          children: [
            _buildTitleBar(context),
            _TrajectoryToolbar(
              actualDuration: _actualDuration,
              allTurnsCollapsed:
                  _collapsibleTurns.isNotEmpty &&
                  _collapsibleTurns.every(_collapsedTurns.contains),
              allCallsCollapsed:
                  _snapshot.assistantCallAnchors.isNotEmpty &&
                  _snapshot.assistantCallAnchors.every(
                    _collapsedCalls.contains,
                  ),
              searchController: _searchController,
              onDurationChanged: () {
                setState(() {
                  _actualDuration = !_actualDuration;
                  _timelineRange = null;
                });
              },
              onToggleTurns: _toggleAllTurns,
              onToggleCalls: _toggleAllCalls,
            ),
            _TrajectoryTimeline(
              records: _snapshot.records,
              actualDuration: _actualDuration,
              selection: _timelineRange,
              searchMatches: _searchMatches,
              hasEarlierRecords: _session.hasMoreHistoricalMessages,
              loadingEarlier: _loadingOlder,
              selectedRecordId: _selectedRecordId,
              onLoadEarlier: _loadOlder,
              onSelectionChanged: (range) {
                setState(() => _timelineRange = range);
              },
              onRecordSelected: _selectRecordFromTimeline,
            ),
            Expanded(child: _buildBody(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildTitleBar(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      height: 44,
      padding: const EdgeInsets.only(left: 14, right: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: _kTrajectoryAssistantColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(7),
            ),
            child: const Icon(
              Icons.route_outlined,
              size: 17,
              color: _kTrajectoryAssistantColor,
            ),
          ),
          kOpenHandHGap10,
          Text(
            openHandTrajectoryLabel(context),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          kOpenHandHGap10,
          Expanded(
            child: Text(
              _session.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (!_loadingInitial)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                _session.messages.isEmpty
                    ? '0 / ${_session.messageTotalCount}'
                    : '${_session.messageWindowStartIndex + 1}-'
                          '${_session.messageWindowStartIndex + _session.messages.length} / '
                          '${_session.messageTotalCount}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          IconButton(
            tooltip: openHandCloseLabel(context),
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, size: 19),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loadingInitial) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            kOpenHandGap12,
            Text(
              openHandLocalizedText(
                context,
                zh: '正在装配轨迹…',
                en: 'Assembling trajectory…',
              ),
            ),
          ],
        ),
      );
    }
    if (_loadError != null) {
      return Center(
        child: _TrajectoryStateMessage(
          icon: Icons.error_outline_rounded,
          title: _loadError!,
          actionLabel: openHandLocalizedText(context, zh: '重试', en: 'Retry'),
          onAction: () {
            setState(() {
              _loadingInitial = true;
              _loadError = null;
            });
            unawaited(_loadInitialWindow());
          },
        ),
      );
    }
    if (_snapshot.records.length == 1 && _session.messageTotalCount == 0) {
      return Center(
        child: _TrajectoryStateMessage(
          icon: Icons.route_outlined,
          title: openHandLocalizedText(
            context,
            zh: '此线程暂无可展示的轨迹',
            en: 'No trajectory is available for this thread',
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= _kTrajectoryDesktopBreakpoint;
        final details = _selectedRecord == null
            ? null
            : _TrajectoryDetailsPanel(
                key: ValueKey<String>(_selectedRecord!.id),
                record: _selectedRecord!,
                metadata: _selectedMetadata,
                metadataLoading: _selectedMetadataLoading,
                activeTab: _activeDetailTab,
                onTabChanged: (tab) => setState(() => _activeDetailTab = tab),
                onClose: _closeDetails,
              );
        final ledger = _buildLedger(context);
        if (!desktop) {
          final motion = openHandMotionDuration(context, kOpenHandMotion220);
          return Column(
            children: [
              Expanded(child: ledger),
              AnimatedContainer(
                duration: motion,
                curve: Curves.easeOutCubic,
                height: details == null
                    ? 0
                    : math.min(360, constraints.maxHeight * 0.48),
                decoration: BoxDecoration(
                  border: details == null
                      ? null
                      : Border(
                          top: BorderSide(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                ),
                child: ClipRect(child: details ?? const SizedBox.shrink()),
              ),
            ],
          );
        }
        final motion = openHandMotionDuration(context, kOpenHandMotion220);
        return Row(
          children: [
            Expanded(child: ledger),
            AnimatedContainer(
              duration: motion,
              curve: Curves.easeOutCubic,
              width: details == null ? 0 : _detailsWidth,
              child: details == null
                  ? const SizedBox.shrink()
                  : Row(
                      children: [
                        MouseRegion(
                          cursor: SystemMouseCursors.resizeColumn,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onHorizontalDragUpdate: (details) {
                              setState(() {
                                _detailsWidth =
                                    (_detailsWidth - details.delta.dx).clamp(
                                      _kTrajectoryDetailsMinWidth,
                                      _kTrajectoryDetailsMaxWidth,
                                    );
                              });
                            },
                            child: Container(
                              width: 5,
                              color: Colors.transparent,
                              child: Center(
                                child: Container(
                                  width: 1,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.outlineVariant,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(child: details),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLedger(BuildContext context) {
    final rows = _ledgerRows;
    if (rows.isEmpty) {
      return Center(
        child: _TrajectoryStateMessage(
          icon: Icons.search_off_rounded,
          title: openHandLocalizedText(
            context,
            zh: '没有匹配的轨迹记录',
            en: 'No trajectory records match',
          ),
          actionLabel: _searchQuery.isEmpty
              ? null
              : openHandLocalizedText(context, zh: '清除搜索', en: 'Clear search'),
          onAction: _searchQuery.isEmpty ? null : _searchController.clear,
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final tableWidth = math.max(
          _kTrajectoryTableMinWidth,
          constraints.maxWidth,
        );
        return Scrollbar(
          controller: _ledgerHorizontalController,
          notificationPredicate: (notification) => notification.depth == 1,
          child: SingleChildScrollView(
            controller: _ledgerHorizontalController,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: tableWidth,
              height: constraints.maxHeight,
              child: Scrollbar(
                controller: _ledgerScrollController,
                child: ListView.builder(
                  controller: _ledgerScrollController,
                  physics: openHandDialogAwareScrollPhysics(context),
                  itemExtent: _kTrajectoryRowHeight,
                  itemCount:
                      rows.length +
                      (_session.hasMoreHistoricalMessages ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (_session.hasMoreHistoricalMessages && index == 0) {
                      return _TrajectoryOlderHistoryRow(
                        loading: _loadingOlder,
                        onPressed: _loadOlder,
                      );
                    }
                    final rowIndex =
                        index - (_session.hasMoreHistoricalMessages ? 1 : 0);
                    final row = rows[rowIndex];
                    final previous = rowIndex > 0 ? rows[rowIndex - 1] : null;
                    final isTurnStart =
                        row.record.turn > 0 &&
                        previous?.record.turn != row.record.turn;
                    final isStepStart =
                        row.record.step > 0 &&
                        (previous?.record.turn != row.record.turn ||
                            previous?.record.step != row.record.step);
                    return _TrajectoryLedgerRecordRow(
                      row: row,
                      isTurnStart: isTurnStart,
                      isStepStart: isStepStart,
                      selected: _selectedRecordId == row.record.id,
                      onPressed: row.summary == null
                          ? () => _selectRecord(row.record)
                          : () {
                              setState(() {
                                if (row.summaryKind == 'turn') {
                                  _collapsedTurns.remove(row.record.turn);
                                } else {
                                  _collapsedCalls.remove(row.record.id);
                                }
                              });
                            },
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TrajectoryStateMessage extends StatelessWidget {
  const _TrajectoryStateMessage({
    required this.icon,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 30, color: colorScheme.onSurfaceVariant),
          kOpenHandGap10,
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            kOpenHandGap12,
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

class _TrajectoryToolbar extends StatelessWidget {
  const _TrajectoryToolbar({
    required this.actualDuration,
    required this.allTurnsCollapsed,
    required this.allCallsCollapsed,
    required this.searchController,
    required this.onDurationChanged,
    required this.onToggleTurns,
    required this.onToggleCalls,
  });

  final bool actualDuration;
  final bool allTurnsCollapsed;
  final bool allCallsCollapsed;
  final TextEditingController searchController;
  final VoidCallback onDurationChanged;
  final VoidCallback onToggleTurns;
  final VoidCallback onToggleCalls;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 590;
          return Row(
            children: [
              _TrajectoryToolbarButton(
                icon: Icons.schedule_outlined,
                label: compact ? null : 'Duration',
                selected: actualDuration,
                tooltip: actualDuration
                    ? 'Use equal-width operations'
                    : 'Use actual duration',
                onPressed: onDurationChanged,
              ),
              _TrajectoryToolbarButton(
                icon: allTurnsCollapsed
                    ? Icons.add_box_outlined
                    : Icons.indeterminate_check_box_outlined,
                label: compact ? null : 'Turns',
                tooltip: allTurnsCollapsed ? 'Expand turns' : 'Collapse turns',
                onPressed: onToggleTurns,
              ),
              _TrajectoryToolbarButton(
                icon: allCallsCollapsed
                    ? Icons.add_box_outlined
                    : Icons.indeterminate_check_box_outlined,
                label: compact ? null : 'Calls',
                tooltip: allCallsCollapsed ? 'Expand calls' : 'Collapse calls',
                onPressed: onToggleCalls,
              ),
              const Spacer(),
              SizedBox(
                width: compact ? 150 : 220,
                height: 30,
                child: TextField(
                  controller: searchController,
                  style: Theme.of(context).textTheme.bodySmall,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: openHandLocalizedText(
                      context,
                      zh: '搜索',
                      en: 'Search',
                    ),
                    prefixIcon: const Icon(Icons.search_rounded, size: 17),
                    suffixIcon: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: searchController,
                      builder: (context, value, _) => value.text.isEmpty
                          ? const SizedBox.shrink()
                          : IconButton(
                              tooltip: openHandLocalizedText(
                                context,
                                zh: '清除搜索',
                                en: 'Clear search',
                              ),
                              onPressed: searchController.clear,
                              icon: const Icon(Icons.close_rounded, size: 15),
                            ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: colorScheme.outlineVariant),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TrajectoryToolbarButton extends StatelessWidget {
  const _TrajectoryToolbarButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
  });

  final IconData icon;
  final String? label;
  final String tooltip;
  final VoidCallback onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Padding(
        padding: const EdgeInsets.only(right: 2),
        child: Material(
          color: selected
              ? colorScheme.primary.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: kOpenHandBorderRadius5,
          child: InkWell(
            onTap: onPressed,
            borderRadius: kOpenHandBorderRadius5,
            child: SizedBox(
              height: 28,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: label == null ? 7 : 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 16, color: colorScheme.onSurfaceVariant),
                    if (label != null) ...[
                      kOpenHandHGap6,
                      Text(
                        label!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TrajectoryTimeline extends StatefulWidget {
  const _TrajectoryTimeline({
    required this.records,
    required this.actualDuration,
    required this.selection,
    required this.searchMatches,
    required this.hasEarlierRecords,
    required this.loadingEarlier,
    required this.selectedRecordId,
    required this.onLoadEarlier,
    required this.onSelectionChanged,
    required this.onRecordSelected,
  });

  final List<_TrajectoryRecord> records;
  final bool actualDuration;
  final _TrajectoryRange? selection;
  final Set<String>? searchMatches;
  final bool hasEarlierRecords;
  final bool loadingEarlier;
  final String? selectedRecordId;
  final Future<void> Function() onLoadEarlier;
  final ValueChanged<_TrajectoryRange?> onSelectionChanged;
  final ValueChanged<_TrajectoryRecord> onRecordSelected;

  @override
  State<_TrajectoryTimeline> createState() => _TrajectoryTimelineState();
}

class _TrajectoryTimelineState extends State<_TrajectoryTimeline> {
  int? _activePointer;
  double? _dragStart;
  _TrajectoryRange? _draft;
  bool _panning = false;
  bool _panMoved = false;
  double _panStartX = 0;
  double _panDomainStart = 0;
  double? _viewportStart;
  double? _viewportEnd;
  _TrajectoryRecord? _hoverRecord;
  double _hoverX = 8;
  late final OpenHandDebouncer _hoverDebouncer = OpenHandDebouncer(
    delay: const Duration(milliseconds: 500),
  );
  DateTime? _lastClickAt;
  double? _lastClickX;

  @override
  void didUpdateWidget(covariant _TrajectoryTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.actualDuration != widget.actualDuration) {
      _viewportStart = null;
      _viewportEnd = null;
      _draft = null;
    }
    if (oldWidget.records.isNotEmpty && widget.records.isNotEmpty) {
      final oldLast = oldWidget.records.last.id;
      final newLast = widget.records.last.id;
      if (oldLast != newLast && _viewportStart == null) {
        _viewportEnd = null;
      }
    }
  }

  @override
  void dispose() {
    _hoverDebouncer.dispose();
    super.dispose();
  }

  void _scheduleHover(_TrajectoryRecord? record) {
    if (_hoverRecord?.id == record?.id) return;
    _hoverDebouncer.cancel();
    if (record == null) {
      if (_hoverRecord != null) setState(() => _hoverRecord = null);
      return;
    }
    _hoverDebouncer.schedule(() {
      if (mounted) setState(() => _hoverRecord = record);
    });
  }

  void _handleHover(
    PointerHoverEvent event,
    double width,
    _TrajectoryProjection projection,
  ) {
    _hoverX = event.localPosition.dx;
    final value = _valueAt(event.localPosition.dx, width, projection);
    _scheduleHover(_spanAt(value, projection)?.record);
  }

  (double, double) _domain(_TrajectoryProjection projection) {
    final fullStart = projection.start;
    final fullEnd = math.max(fullStart + 1, projection.end);
    final start = (_viewportStart ?? fullStart).clamp(fullStart, fullEnd - 1);
    final end = (_viewportEnd ?? fullEnd).clamp(start + 1, fullEnd);
    return (start.toDouble(), end.toDouble());
  }

  double _valueAt(
    double localX,
    double width,
    _TrajectoryProjection projection,
  ) {
    final domain = _domain(projection);
    final fraction = (localX / math.max(1, width)).clamp(0.0, 1.0);
    return domain.$1 + (domain.$2 - domain.$1) * fraction;
  }

  _TrajectorySpan? _spanAt(double value, _TrajectoryProjection projection) {
    _TrajectorySpan? nearest;
    var nearestDistance = double.infinity;
    for (final span in projection.spans) {
      if (value >= span.start && value <= span.end) return span;
      final distance = math.min(
        (value - span.start).abs(),
        (value - span.end).abs(),
      );
      if (distance < nearestDistance) {
        nearest = span;
        nearestDistance = distance;
      }
    }
    return nearest;
  }

  void _handlePointerDown(
    PointerDownEvent event,
    double width,
    _TrajectoryProjection projection,
  ) {
    if (_activePointer != null) return;
    _activePointer = event.pointer;
    if ((event.buttons & kSecondaryMouseButton) != 0) {
      final domain = _domain(projection);
      final fullDuration = projection.end - projection.start;
      if (domain.$2 - domain.$1 < fullDuration - 0.5) {
        _panning = true;
        _panMoved = false;
        _panStartX = event.localPosition.dx;
        _panDomainStart = domain.$1;
      } else {
        widget.onSelectionChanged(null);
      }
      return;
    }
    final value = _valueAt(event.localPosition.dx, width, projection);
    _dragStart = value;
    _draft = _TrajectoryRange(value, value);
    setState(() {});
  }

  void _handlePointerMove(
    PointerMoveEvent event,
    double width,
    _TrajectoryProjection projection,
  ) {
    if (_activePointer == event.pointer && _panning) {
      final domain = _domain(projection);
      final duration = domain.$2 - domain.$1;
      final delta =
          (event.localPosition.dx - _panStartX) / math.max(1, width) * duration;
      final maxStart = math.max(projection.start, projection.end - duration);
      final start = (_panDomainStart - delta).clamp(projection.start, maxStart);
      _panMoved = _panMoved || delta.abs() > duration * 0.003;
      setState(() {
        _viewportStart = start.toDouble();
        _viewportEnd = start + duration;
      });
      return;
    }
    final dragStart = _dragStart;
    if (_activePointer == event.pointer && dragStart != null) {
      final value = _valueAt(event.localPosition.dx, width, projection);
      final range = _TrajectoryRange(
        math.min(dragStart, value),
        math.max(dragStart, value),
      );
      setState(() => _draft = range);
      widget.onSelectionChanged(range);
      return;
    }
    final value = _valueAt(event.localPosition.dx, width, projection);
    _scheduleHover(_spanAt(value, projection)?.record);
  }

  void _handlePointerUp(
    PointerEvent event,
    double width,
    _TrajectoryProjection projection,
  ) {
    if (_activePointer != event.pointer) return;
    if (_panning) {
      if (!_panMoved) widget.onSelectionChanged(null);
      _panning = false;
      _activePointer = null;
      return;
    }
    final start = _dragStart;
    final end = _valueAt(event.localPosition.dx, width, projection);
    _activePointer = null;
    _dragStart = null;
    if (start == null) return;
    final domain = _domain(projection);
    final isClick = (end - start).abs() < (domain.$2 - domain.$1) * 0.006;
    if (isClick) {
      final now = DateTime.now();
      final doubleClick =
          _lastClickAt != null &&
          now.difference(_lastClickAt!) < const Duration(milliseconds: 350) &&
          (_lastClickX! - event.localPosition.dx).abs() < 8;
      _lastClickAt = now;
      _lastClickX = event.localPosition.dx;
      if (doubleClick) {
        widget.onSelectionChanged(null);
      } else {
        final span = _spanAt(end, projection);
        if (span != null) {
          widget.onSelectionChanged(null);
          widget.onRecordSelected(span.record);
        }
      }
      setState(() => _draft = null);
      return;
    }
    final range = _TrajectoryRange(math.min(start, end), math.max(start, end));
    setState(() => _draft = null);
    widget.onSelectionChanged(range);
  }

  void _handleScroll(
    PointerScrollEvent event,
    double width,
    _TrajectoryProjection projection,
  ) {
    final fullDuration = math.max(1.0, projection.end - projection.start);
    final domain = _domain(projection);
    final currentDuration = domain.$2 - domain.$1;
    final factor = math.exp(event.scrollDelta.dy * 0.0015);
    final nextDuration = (currentDuration * factor).clamp(
      math.max(1.0, fullDuration * 0.035),
      fullDuration,
    );
    final anchorFraction = (event.localPosition.dx / math.max(1, width)).clamp(
      0.0,
      1.0,
    );
    final anchor = domain.$1 + currentDuration * anchorFraction;
    var start = anchor - nextDuration * anchorFraction;
    start = start.clamp(
      projection.start,
      math.max(projection.start, projection.end - nextDuration),
    );
    setState(() {
      if ((nextDuration - fullDuration).abs() < 0.5) {
        _viewportStart = null;
        _viewportEnd = null;
      } else {
        _viewportStart = start.toDouble();
        _viewportEnd = start + nextDuration;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final projection = _trajectoryProjection(
      widget.records,
      actualDuration: widget.actualDuration,
    );
    final domain = _domain(projection);
    final selection = _draft ?? widget.selection;
    return Container(
      height: 58,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 54,
            child: Stack(
              children: [
                Positioned(
                  top: 7,
                  right: 5,
                  child: Text(
                    'Input',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontSize: 10,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Positioned(
                  top: 24,
                  right: 5,
                  child: Text(
                    'Model',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontSize: 10,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Positioned(
                  top: 41,
                  right: 5,
                  child: Text(
                    'Tools',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontSize: 10,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          VerticalDivider(width: 1, color: colorScheme.outlineVariant),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                return Listener(
                  onPointerDown: (event) =>
                      _handlePointerDown(event, width, projection),
                  onPointerMove: (event) =>
                      _handlePointerMove(event, width, projection),
                  onPointerHover: (event) =>
                      _handleHover(event, width, projection),
                  onPointerUp: (event) =>
                      _handlePointerUp(event, width, projection),
                  onPointerCancel: (event) =>
                      _handlePointerUp(event, width, projection),
                  onPointerSignal: (event) {
                    if (event is PointerScrollEvent) {
                      _handleScroll(event, width, projection);
                    }
                  },
                  child: MouseRegion(
                    cursor: _panning
                        ? SystemMouseCursors.grabbing
                        : SystemMouseCursors.precise,
                    onExit: (_) => _scheduleHover(null),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CustomPaint(
                          painter: _TrajectoryTimelinePainter(
                            projection: projection,
                            domainStart: domain.$1,
                            domainEnd: domain.$2,
                            selection: selection,
                            searchMatches: widget.searchMatches,
                            selectedRecordId: widget.selectedRecordId,
                            hoveredRecordId: _hoverRecord?.id,
                            colorScheme: colorScheme,
                          ),
                        ),
                        if (widget.hasEarlierRecords)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Tooltip(
                              message: openHandLocalizedText(
                                context,
                                zh: '加载更早轨迹',
                                en: 'Load earlier trajectory',
                              ),
                              child: InkWell(
                                onTap: widget.loadingEarlier
                                    ? null
                                    : widget.onLoadEarlier,
                                child: Container(
                                  width: 28,
                                  alignment: Alignment.center,
                                  color: colorScheme.surfaceContainer
                                      .withValues(alpha: 0.86),
                                  child: widget.loadingEarlier
                                      ? const SizedBox(
                                          width: 12,
                                          height: 12,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 1.6,
                                          ),
                                        )
                                      : Text(
                                          '…',
                                          style: Theme.of(
                                            context,
                                          ).textTheme.titleMedium,
                                        ),
                                ),
                              ),
                            ),
                          ),
                        if (_hoverRecord != null)
                          Positioned(
                            left: (_hoverX - 80).clamp(
                              8,
                              math.max(8, width - math.max(160, width * 0.48)),
                            ),
                            bottom: 2,
                            child: IgnorePointer(
                              child: Container(
                                constraints: BoxConstraints(
                                  maxWidth: math.max(120, width * 0.48),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: colorScheme.inverseSurface,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '${_trajectoryKindLabel(_hoverRecord!.kind)} · '
                                  '${_trajectoryDurationLabel(_hoverRecord!.durationMs)} · '
                                  '${_hoverRecord!.preview}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: colorScheme.onInverseSurface,
                                      ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TrajectoryTimelinePainter extends CustomPainter {
  const _TrajectoryTimelinePainter({
    required this.projection,
    required this.domainStart,
    required this.domainEnd,
    required this.selection,
    required this.searchMatches,
    required this.selectedRecordId,
    required this.hoveredRecordId,
    required this.colorScheme,
  });

  final _TrajectoryProjection projection;
  final double domainStart;
  final double domainEnd;
  final _TrajectoryRange? selection;
  final Set<String>? searchMatches;
  final String? selectedRecordId;
  final String? hoveredRecordId;
  final ColorScheme colorScheme;

  double _x(double value, double width) =>
      (value - domainStart) / math.max(1, domainEnd - domainStart) * width;

  @override
  void paint(Canvas canvas, Size size) {
    final boundaryPaint = Paint()
      ..color = colorScheme.outlineVariant.withValues(alpha: 0.72)
      ..strokeWidth = 1;
    for (final entry in projection.turnBoundaries.entries) {
      if (entry.key <= 0 ||
          entry.value < domainStart ||
          entry.value > domainEnd) {
        continue;
      }
      final x = _x(entry.value, size.width);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), boundaryPaint);
    }
    final activeSelection = selection;
    if (activeSelection != null) {
      final left = _x(activeSelection.start, size.width).clamp(0.0, size.width);
      final right = _x(activeSelection.end, size.width).clamp(0.0, size.width);
      final outside = Paint()
        ..color = colorScheme.surface.withValues(alpha: 0.6);
      canvas.drawRect(Rect.fromLTRB(0, 0, left, size.height), outside);
      canvas.drawRect(
        Rect.fromLTRB(right, 0, size.width, size.height),
        outside,
      );
      final selectedPaint = Paint()
        ..color = colorScheme.primary.withValues(alpha: 0.1);
      canvas.drawRect(
        Rect.fromLTRB(left, 0, right, size.height),
        selectedPaint,
      );
      final edgePaint = Paint()
        ..color = colorScheme.primary
        ..strokeWidth = 2;
      canvas.drawLine(Offset(left, 0), Offset(left, size.height), edgePaint);
      canvas.drawLine(Offset(right, 0), Offset(right, size.height), edgePaint);
    }
    for (final span in projection.spans) {
      if (span.end < domainStart || span.start > domainEnd) continue;
      var opacity = 1.0;
      if (activeSelection != null &&
          (span.start > activeSelection.end ||
              span.end < activeSelection.start)) {
        opacity = 0.2;
      }
      if (searchMatches != null && !searchMatches!.contains(span.record.id)) {
        opacity = math.min(opacity, 0.14);
      }
      final left = _x(span.start, size.width);
      final right = _x(span.end, size.width);
      final width = math.max(2.0, right - left - 2);
      final top = 7.0 + span.record.lane * 17;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left + 1, top, width, 8),
        const Radius.circular(1.5),
      );
      final color = span.record.isError
          ? _kTrajectoryErrorColor
          : _trajectoryKindColor(span.record.kind);
      canvas.drawRRect(rect, Paint()..color = color.withValues(alpha: opacity));
      if (span.record.id == selectedRecordId ||
          span.record.id == hoveredRecordId) {
        final outline = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = colorScheme.primary;
        canvas.drawRRect(rect.inflate(2), outline);
      }
    }
    if (projection.spans.isEmpty) {
      final painter = TextPainter(
        text: TextSpan(
          text: 'No timing data',
          style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 11),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        Offset(
          (size.width - painter.width) / 2,
          (size.height - painter.height) / 2,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TrajectoryTimelinePainter oldDelegate) {
    return oldDelegate.projection != projection ||
        oldDelegate.domainStart != domainStart ||
        oldDelegate.domainEnd != domainEnd ||
        oldDelegate.selection != selection ||
        oldDelegate.searchMatches != searchMatches ||
        oldDelegate.selectedRecordId != selectedRecordId ||
        oldDelegate.hoveredRecordId != hoveredRecordId ||
        oldDelegate.colorScheme != colorScheme;
  }
}

class _TrajectoryOlderHistoryRow extends StatelessWidget {
  const _TrajectoryOlderHistoryRow({
    required this.loading,
    required this.onPressed,
  });

  final bool loading;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: loading ? null : onPressed,
      icon: loading
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 1.8),
            )
          : const Icon(Icons.more_horiz_rounded, size: 18),
      label: Text(
        loading
            ? openHandLocalizedText(
                context,
                zh: '正在加载更早轨迹…',
                en: 'Loading earlier trajectory…',
              )
            : openHandLocalizedText(
                context,
                zh: '加载更早轨迹',
                en: 'Load earlier trajectory',
              ),
      ),
    );
  }
}

class _TrajectoryLedgerRecordRow extends StatelessWidget {
  const _TrajectoryLedgerRecordRow({
    required this.row,
    required this.isTurnStart,
    required this.isStepStart,
    required this.selected,
    required this.onPressed,
  });

  final _TrajectoryLedgerRow row;
  final bool isTurnStart;
  final bool isStepStart;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final record = row.record;
    final accent = record.isError
        ? _kTrajectoryErrorColor
        : _trajectoryKindColor(record.kind);
    final summary = row.summary;
    return Material(
      color: selected
          ? colorScheme.primary.withValues(alpha: 0.08)
          : Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        hoverColor: colorScheme.onSurface.withValues(alpha: 0.045),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              top: isStepStart
                  ? BorderSide(color: colorScheme.outlineVariant, width: 1.25)
                  : BorderSide.none,
              bottom: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.72),
              ),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: _kTrajectoryTurnRailWidth,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned(
                      left: 34,
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: selected ? 2 : 1,
                        color: selected
                            ? colorScheme.primary
                            : colorScheme.outlineVariant,
                      ),
                    ),
                    if (isStepStart)
                      Positioned(
                        left: 30,
                        top: 20,
                        child: Tooltip(
                          message: record.requestNumber > 0
                              ? 'Request #${record.requestNumber}'
                              : 'Step ${record.step}',
                          child: Container(
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(
                              color: selected ? colorScheme.primary : accent,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: colorScheme.surface,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (isTurnStart)
                      Positioned(
                        left: 3,
                        top: 2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            'Turn ${record.turn}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(
                width: _kTrajectoryKindWidth,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _TrajectoryKindTag(record: record),
                ),
              ),
              Expanded(
                child: summary == null
                    ? Row(
                        children: [
                          Expanded(
                            child: Text(
                              record.preview.isEmpty
                                  ? 'No content'
                                  : record.preview,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontFamily: record.kind == _TrajectoryKind.tool
                                    ? 'monospace'
                                    : null,
                              ),
                            ),
                          ),
                          if (record.running) ...[
                            kOpenHandHGap8,
                            SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.6,
                                color: accent,
                              ),
                            ),
                          ],
                        ],
                      )
                    : Row(
                        children: [
                          Icon(
                            Icons.more_horiz_rounded,
                            size: 18,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          kOpenHandHGap8,
                          Expanded(
                            child: Text(
                              summary,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
              if (summary == null) ...[
                SizedBox(
                  width: 58,
                  child: Text(
                    record.usage?.promptTokens?.toString() ?? '',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                SizedBox(
                  width: 58,
                  child: Text(
                    record.usage?.completionTokens?.toString() ?? '',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                SizedBox(
                  width: 76,
                  child: Text(
                    _trajectoryDurationLabel(record.durationMs),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: record.isError
                          ? _kTrajectoryErrorColor
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ] else
                const SizedBox(width: 192),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrajectoryKindTag extends StatelessWidget {
  const _TrajectoryKindTag({required this.record});

  final _TrajectoryRecord record;

  @override
  Widget build(BuildContext context) {
    final accent = record.isError
        ? _kTrajectoryErrorColor
        : _trajectoryKindColor(record.kind);
    return Container(
      constraints: const BoxConstraints(maxWidth: 104),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.15),
        borderRadius: kOpenHandBorderRadius5,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_trajectoryKindIcon(record.kind), size: 13, color: accent),
          kOpenHandHGap5,
          Flexible(
            child: Text(
              _trajectoryKindLabel(record.kind),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: accent,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Color _trajectoryKindColor(_TrajectoryKind kind) => switch (kind) {
  _TrajectoryKind.system => _kTrajectorySystemColor,
  _TrajectoryKind.user => _kTrajectoryUserColor,
  _TrajectoryKind.context => _kTrajectoryContextColor,
  _TrajectoryKind.compacted => _kTrajectorySystemColor,
  _TrajectoryKind.assistant => _kTrajectoryAssistantColor,
  _TrajectoryKind.tool || _TrajectoryKind.subtool => _kTrajectoryToolColor,
};

IconData _trajectoryKindIcon(_TrajectoryKind kind) => switch (kind) {
  _TrajectoryKind.system => Icons.settings_outlined,
  _TrajectoryKind.user => Icons.person_outline_rounded,
  _TrajectoryKind.context => Icons.info_outline_rounded,
  _TrajectoryKind.compacted => Icons.compress_rounded,
  _TrajectoryKind.assistant => Icons.auto_awesome_outlined,
  _TrajectoryKind.tool || _TrajectoryKind.subtool => Icons.build_outlined,
};

String _trajectoryKindLabel(_TrajectoryKind kind) => switch (kind) {
  _TrajectoryKind.system => 'SYSTEM',
  _TrajectoryKind.user => 'USER',
  _TrajectoryKind.context => 'CONTEXT',
  _TrajectoryKind.compacted => 'COMPACTED',
  _TrajectoryKind.assistant => 'ASSISTANT',
  _TrajectoryKind.tool => 'TOOL',
  _TrajectoryKind.subtool => 'SUBTOOL',
};

String _trajectoryDurationLabel(int? milliseconds) {
  if (milliseconds == null) return '—';
  if (milliseconds < 1000) return '$milliseconds ms';
  final seconds = milliseconds / 1000;
  return '${seconds.toStringAsFixed(seconds < 10 ? 2 : 1)} s';
}

List<(String, String)> _trajectoryDetailTabs(_TrajectoryRecord record) {
  return switch (record.kind) {
    _TrajectoryKind.system => const <(String, String)>[
      ('system-prompt', 'System Prompt'),
      ('tools', 'Tools'),
    ],
    _TrajectoryKind.user || _TrajectoryKind.context => const <(String, String)>[
      ('summary', 'Summary'),
      ('rendered', 'Rendered'),
      ('raw', 'Raw'),
      ('source', 'Source'),
      ('timing', 'Timing'),
    ],
    _TrajectoryKind.assistant => const <(String, String)>[
      ('summary', 'Summary'),
      ('rendered', 'Rendered'),
      ('raw', 'Raw'),
      ('options', 'Options'),
      ('usage', 'Usage'),
      ('timing', 'Timing'),
    ],
    _TrajectoryKind.compacted => const <(String, String)>[
      ('summary', 'Summary'),
      ('raw', 'Raw Output'),
    ],
    _TrajectoryKind.tool || _TrajectoryKind.subtool => const <(String, String)>[
      ('summary', 'Summary'),
      ('input', 'Input'),
      ('output', 'Output'),
      ('schema', 'Schema'),
      ('timing', 'Timing'),
    ],
  };
}

class _TrajectoryDetailsPanel extends StatelessWidget {
  const _TrajectoryDetailsPanel({
    super.key,
    required this.record,
    required this.metadata,
    required this.metadataLoading,
    required this.activeTab,
    required this.onTabChanged,
    required this.onClose,
  });

  final _TrajectoryRecord record;
  final Map<String, Object?> metadata;
  final bool metadataLoading;
  final String activeTab;
  final ValueChanged<String> onTabChanged;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tabs = _trajectoryDetailTabs(record);
    final effectiveTab = tabs.any((tab) => tab.$1 == activeTab)
        ? activeTab
        : tabs.first.$1;
    return ColoredBox(
      color: colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 44,
            child: Padding(
              padding: const EdgeInsets.only(left: 12, right: 4),
              child: Row(
                children: [
                  _TrajectoryKindTag(record: record),
                  kOpenHandHGap8,
                  Expanded(
                    child: Text(
                      record.turn > 0
                          ? 'Turn ${record.turn} · Step ${record.step}'
                          : record.preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (metadataLoading)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(strokeWidth: 1.7),
                      ),
                    ),
                  IconButton(
                    tooltip: openHandLocalizedText(
                      context,
                      zh: '关闭详情',
                      en: 'Close details',
                    ),
                    onPressed: onClose,
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            height: 38,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  for (final tab in tabs)
                    _TrajectoryDetailTab(
                      label: tab.$2,
                      selected: tab.$1 == effectiveTab,
                      onPressed: () => onTabChanged(tab.$1),
                    ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: colorScheme.outlineVariant),
          Expanded(
            child: _TrajectoryDetailBody(
              record: record,
              metadata: metadata,
              activeTab: effectiveTab,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrajectoryDetailTab extends StatelessWidget {
  const _TrajectoryDetailTab({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onPressed,
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? colorScheme.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: selected
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _TrajectoryDetailBody extends StatelessWidget {
  const _TrajectoryDetailBody({
    required this.record,
    required this.metadata,
    required this.activeTab,
  });

  final _TrajectoryRecord record;
  final Map<String, Object?> metadata;
  final String activeTab;

  @override
  Widget build(BuildContext context) {
    final content = switch (activeTab) {
      'summary' => _buildSummary(context),
      'system-prompt' => _TrajectoryMarkdownDetail(
        text: _trajectorySystemPrompt(metadata),
        emptyText: 'No system prompt in this request',
      ),
      'tools' => _TrajectoryTextDetail(
        text: _trajectoryToolCatalog(metadata),
        emptyText: 'No tool catalog in this request',
        monospace: true,
      ),
      'rendered' => _TrajectoryMarkdownDetail(
        text: _trajectoryRecordRawText(record),
        emptyText: 'No content',
      ),
      'raw' => _TrajectoryTextDetail(
        text: _trajectoryRecordRawText(record),
        emptyText: 'No content',
        monospace: true,
      ),
      'source' => _TrajectoryTextDetail(
        text: _trajectoryPrettyValue(<String, Object?>{
          'message_id': record.sourceMessageId,
          'turn': record.turn,
          'step': record.step,
          'request_number': record.requestNumber,
          'metadata': metadata,
        }),
        emptyText: 'Source not recorded',
        monospace: true,
      ),
      'input' => _TrajectoryTextDetail(
        text: record.input,
        emptyText: 'No input payload',
        monospace: true,
      ),
      'output' => _TrajectoryTextDetail(
        text: record.output,
        emptyText: record.running ? 'Pending' : 'No output payload',
        monospace: true,
        error: record.isError,
      ),
      'schema' => _TrajectoryTextDetail(
        text: _trajectorySchema(metadata),
        emptyText: 'Schema not recorded',
        monospace: true,
      ),
      'options' => _TrajectoryTextDetail(
        text: _trajectoryRequestOptions(metadata),
        emptyText: 'Options not recorded',
        monospace: true,
      ),
      'usage' => _buildUsage(context),
      'timing' => _buildTiming(context),
      _ => const SizedBox.shrink(),
    };
    return Scrollbar(
      child: SingleChildScrollView(
        physics: openHandDialogAwareScrollPhysics(context),
        padding: const EdgeInsets.all(14),
        child: content,
      ),
    );
  }

  Widget _buildSummary(BuildContext context) {
    final status = record.isError
        ? 'Failed'
        : record.running
        ? 'Pending'
        : 'Completed';
    final model =
        record.metadata['model'] ??
        record.metadata['model_id'] ??
        metadata['model'] ??
        metadata['model_id'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TrajectoryOverview(
          rows: <(String, String, bool)>[
            ('Status', status, record.isError),
            if (model != null) ('Model', '$model', false),
            if (record.toolName != null) ('Tool', record.toolName!, false),
            if (record.callId != null) ('Call ID', record.callId!, false),
            if (record.kind == _TrajectoryKind.assistant)
              (
                'Tokens',
                record.usage?.completionTokens == null
                    ? '—'
                    : '${record.usage!.completionTokens} tok',
                false,
              ),
            ('Duration', _trajectoryDurationLabel(record.durationMs), false),
          ],
        ),
        if (_trajectoryRecordRawText(record).isNotEmpty) ...[
          kOpenHandGap16,
          _TrajectoryOverviewSection(
            title: record.kind == _TrajectoryKind.tool ? 'Result' : 'Preview',
            child: _TrajectoryMarkdownDetail(
              text: _trajectoryRecordRawText(record),
              emptyText: 'No content',
              preview: true,
            ),
          ),
        ],
        if (record.kind == _TrajectoryKind.assistant) ...[
          kOpenHandGap16,
          _TrajectoryOverviewSection(
            title: 'Usage',
            child: _buildUsage(context, compact: true),
          ),
          kOpenHandGap16,
          _TrajectoryOverviewSection(
            title: 'Timing',
            child: _buildTiming(context, compact: true),
          ),
        ],
      ],
    );
  }

  Widget _buildUsage(BuildContext context, {bool compact = false}) {
    final usage = record.usage;
    if (usage == null || usage.isEmpty) {
      return const _TrajectoryEmptyDetail(text: 'Usage not reported');
    }
    final contentTokens =
        usage.completionTokens != null && usage.reasoningTokens != null
        ? math.max(0, usage.completionTokens! - usage.reasoningTokens!)
        : null;
    return _TrajectoryOverview(
      compact: compact,
      rows: <(String, String, bool)>[
        if (usage.promptTokens != null)
          ('Input', '${usage.promptTokens} tok', false),
        if (usage.cacheReadTokens != null)
          ('Cached', '${usage.cacheReadTokens} tok', false),
        if (usage.cacheCreationTokens != null)
          ('Cache created', '${usage.cacheCreationTokens} tok', false),
        if (usage.completionTokens != null)
          ('Output', '${usage.completionTokens} tok', false),
        if (usage.reasoningTokens != null)
          ('Reasoning', '${usage.reasoningTokens} tok', false),
        if (contentTokens != null) ('Content', '$contentTokens tok', false),
        if (usage.resolvedTotalTokens != null)
          ('Total', '${usage.resolvedTotalTokens} tok', false),
      ],
    );
  }

  Widget _buildTiming(BuildContext context, {bool compact = false}) {
    final firstToken = _trajectoryMetadataDate(metadata, const <String>[
      'first_token_at',
      'first_token_time',
      'first_visible_at',
    ]);
    final startedAt = record.startedAt;
    final ttft = startedAt != null && firstToken != null
        ? math.max(0, firstToken.difference(startedAt).inMilliseconds)
        : null;
    final generation = record.durationMs != null && ttft != null
        ? math.max(0, record.durationMs! - ttft)
        : null;
    final outputTokens = record.usage?.completionTokens;
    final throughput =
        outputTokens != null && generation != null && generation > 0
        ? '${(outputTokens / generation * 1000).toStringAsFixed(1)} tok/s'
        : 'Not recorded';
    return _TrajectoryOverview(
      compact: compact,
      rows: <(String, String, bool)>[
        ('Started', _trajectoryDateTimeLabel(startedAt), false),
        ('Total duration', _trajectoryDurationLabel(record.durationMs), false),
        (
          'TTFT',
          ttft == null ? 'Not recorded' : _trajectoryDurationLabel(ttft),
          false,
        ),
        (
          'Generation',
          generation == null
              ? 'Not recorded'
              : _trajectoryDurationLabel(generation),
          false,
        ),
        ('Throughput', throughput, false),
      ],
    );
  }
}

class _TrajectoryOverview extends StatelessWidget {
  const _TrajectoryOverview({required this.rows, this.compact = false});

  final List<(String, String, bool)> rows;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Column(
      children: [
        for (final row in rows)
          Padding(
            padding: EdgeInsets.symmetric(vertical: compact ? 3 : 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 96,
                  child: Text(
                    row.$1,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Expanded(
                  child: SelectableText(
                    row.$2,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: row.$3 ? _kTrajectoryErrorColor : null,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _TrajectoryOverviewSection extends StatelessWidget {
  const _TrajectoryOverviewSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            kOpenHandHGap8,
            Expanded(child: Divider(color: colorScheme.outlineVariant)),
          ],
        ),
        kOpenHandGap8,
        child,
      ],
    );
  }
}

class _TrajectoryMarkdownDetail extends StatelessWidget {
  const _TrajectoryMarkdownDetail({
    required this.text,
    required this.emptyText,
    this.preview = false,
  });

  final String text;
  final String emptyText;
  final bool preview;

  @override
  Widget build(BuildContext context) {
    if (text.trim().isEmpty) return _TrajectoryEmptyDetail(text: emptyText);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: preview ? 220 : double.infinity),
      child: SelectionArea(
        child: MarkdownBody(
          data: text,
          styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
            p: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.5),
            code: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
          ),
        ),
      ),
    );
  }
}

class _TrajectoryTextDetail extends StatelessWidget {
  const _TrajectoryTextDetail({
    required this.text,
    required this.emptyText,
    this.monospace = false,
    this.error = false,
  });

  final String text;
  final String emptyText;
  final bool monospace;
  final bool error;

  @override
  Widget build(BuildContext context) {
    if (text.trim().isEmpty) return _TrajectoryEmptyDetail(text: emptyText);
    final theme = Theme.of(context);
    return SelectableText(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        fontFamily: monospace ? 'monospace' : null,
        color: error ? _kTrajectoryErrorColor : null,
        height: 1.5,
      ),
    );
  }
}

class _TrajectoryEmptyDetail extends StatelessWidget {
  const _TrajectoryEmptyDetail({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontStyle: FontStyle.italic,
      ),
    );
  }
}

String _trajectoryRecordRawText(_TrajectoryRecord record) {
  if (record.kind == _TrajectoryKind.tool ||
      record.kind == _TrajectoryKind.subtool) {
    return <String>[
      if (record.input.trim().isNotEmpty) record.input,
      if (record.output.trim().isNotEmpty) record.output,
    ].join('\n\n');
  }
  if (record.thinking.trim().isNotEmpty) return record.thinking;
  if (record.output.trim().isNotEmpty) return record.output;
  return record.input;
}

String _trajectorySystemPrompt(Map<String, Object?> metadata) {
  final payload = _trajectoryRequestPayload(metadata);
  final messages = payload['messages'];
  if (messages is List) {
    final systemParts = <String>[];
    for (final item in messages) {
      final message = stringKeyedMapFromValue(item);
      if ('${message['role'] ?? ''}'.toLowerCase() != 'system') continue;
      final content = _trajectoryContentText(message['content']);
      if (content.isNotEmpty) systemParts.add(content);
    }
    if (systemParts.isNotEmpty) return systemParts.join('\n\n');
  }
  return '${metadata['composed_prompt_text'] ?? ''}'.trim();
}

String _trajectoryToolCatalog(Map<String, Object?> metadata) {
  final payload = _trajectoryRequestPayload(metadata);
  final tools = payload['tools'];
  return tools == null ? '' : _trajectoryPrettyValue(tools);
}

String _trajectoryRequestOptions(Map<String, Object?> metadata) {
  final payload = Map<String, Object?>.from(
    _trajectoryRequestPayload(metadata),
  );
  payload.remove('messages');
  payload.remove('tools');
  return payload.isEmpty ? '' : _trajectoryPrettyValue(payload);
}

String _trajectorySchema(Map<String, Object?> metadata) {
  for (final key in const <String>[
    'tool_schema',
    'input_schema',
    'parameters_schema',
    'schema',
  ]) {
    if (metadata[key] != null) return _trajectoryPrettyValue(metadata[key]);
  }
  return '';
}

Map<String, Object?> _trajectoryRequestPayload(Map<String, Object?> metadata) {
  final raw = metadata['request_payload'];
  if (raw == null) return const <String, Object?>{};
  return stringKeyedMapFromValueOrJsonText(raw);
}

String _trajectoryContentText(Object? content) {
  if (content is String) return content.trim();
  if (content is! List) return content == null ? '' : '$content'.trim();
  final parts = <String>[];
  for (final item in content) {
    if (item is String) {
      if (item.trim().isNotEmpty) parts.add(item.trim());
      continue;
    }
    final block = stringKeyedMapFromValue(item);
    final text = '${block['text'] ?? block['content'] ?? ''}'.trim();
    if (text.isNotEmpty) parts.add(text);
  }
  return parts.join('\n');
}

String _trajectoryPrettyValue(Object? value) {
  if (value == null) return '';
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    try {
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(trimmed));
    } on FormatException {
      return trimmed;
    }
  }
  try {
    return const JsonEncoder.withIndent('  ').convert(value);
  } on JsonUnsupportedObjectError {
    return '$value';
  }
}

String _trajectoryDateTimeLabel(DateTime? value) {
  if (value == null) return 'Not available';
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  String three(int number) => number.toString().padLeft(3, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}:${two(local.second)}.'
      '${three(local.millisecond)}';
}

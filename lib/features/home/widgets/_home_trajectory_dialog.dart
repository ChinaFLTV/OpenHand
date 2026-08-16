part of '../openhand_home_page.dart';

const double _kTrajectoryRowHeight = 48;
const double _kTrajectoryToolbarHeight = 48;
const double _kTrajectoryToolbarControlHeight = 36;
const double _kTrajectoryHeaderIconSize = 46;
const double _kTrajectoryHeaderActionSize = 40;
const double _kTrajectoryDetailsActionSize = 26;
const double _kTrajectoryDetailsActionIconSize = 16;
const double _kTrajectoryTurnRailWidth = 68;
const double _kTrajectoryKindWidth = 112;
const double _kTrajectoryDetailsMinWidth = 320;
const double _kTrajectoryDetailsMaxWidth = 560;
const double _kTrajectoryDesktopBreakpoint = 820;
const double _kTrajectoryTableMinWidth = 760;
const double _kTrajectoryOlderLoadThreshold = 48;
const double _kTrajectoryPreviewMaxHeight = 220;
const Duration _kTrajectoryRefreshDelay = Duration(milliseconds: 120);
const int _kTrajectoryJsonTreeMaxCharacters = 512 * kBytesPerKiB;
const int _kTrajectoryJsonTreeMaxNodes = 4096;
const int _kTrajectoryJsonTreeMaxDepth = 32;
const int _kTrajectoryThroughputMaxPoints = 300;
const Duration _kTrajectoryCopyFeedbackDuration = Duration(seconds: 2);

const _kTrajectoryTimelineLightColors = (
  system: Color(0xFF61666B),
  user: Color(0xFF4176E6),
  context: Color(0xFF36A762),
  assistant: Color(0xFF886BAE),
  tool: Color(0xFFDD8629),
  error: Color(0xFFEC1313),
);
const _kTrajectoryTimelineDarkColors = (
  system: Color(0xFFCFD3D6),
  user: Color(0xFF679EFE),
  context: Color(0xFF59D784),
  assistant: Color(0xFF9474BC),
  tool: Color(0xFFDD8629),
  error: Color(0xFFF25A5A),
);
const _kTrajectoryJsonLightColors = (
  key: Color(0xFF0B6E75),
  string: Color(0xFF2F5FA7),
  number: Color(0xFF8B3F8F),
  boolValue: Color(0xFFB45309),
  nullValue: Color(0xFFBE3455),
  punctuation: Color(0xFF667085),
  count: Color(0xFF6D4AC8),
);
const _kTrajectoryJsonDarkColors = (
  key: Color(0xFF67D4D0),
  string: Color(0xFF8CB8FF),
  number: Color(0xFFE69BD3),
  boolValue: Color(0xFFF7B955),
  nullValue: Color(0xFFFF8296),
  punctuation: Color(0xFFAAB3C2),
  count: Color(0xFFB6A0FF),
);

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

String _trajectoryText(
  BuildContext context, {
  required String zh,
  required String en,
  String? zhHant,
  String? fr,
  String? de,
  String? ja,
}) {
  return openHandLocalizedText(
    context,
    zh: zh,
    zhHant: zhHant,
    en: en,
    fr: fr,
    de: de,
    ja: ja,
  );
}

class _TrajectorySnapshot {
  const _TrajectorySnapshot({
    required this.records,
    required this.turnIds,
    required this.collapsibleTurnIds,
    required this.toolRecordIds,
  });

  final List<_TrajectoryRecord> records;
  final Set<int> turnIds;
  final Set<int> collapsibleTurnIds;
  final Set<String> toolRecordIds;

  static _TrajectorySnapshot fromSession(AiSession session) {
    final messages = session.messages
        .where((message) => !message.isDeleted)
        .toList(growable: false);
    final resultByCallId = <String, AiSessionMessage>{};
    final pairedResultIds = <String>{};
    for (final message in messages) {
      if (!message.kind.isToolResultKind) continue;
      final callId =
          '${message.metadata[aiSessionMessageToolCallIdMetadataKey] ?? ''}'
              .trim();
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
        preview: openHandAmbientText(
          zh: '初始系统提示词',
          zhHant: '初始系統提示詞',
          en: 'Initial System Prompt',
          fr: 'Prompt système initial',
          de: 'Initialer System-Prompt',
          ja: '初期システムプロンプト',
        ),
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
      final callId = '${metadata[aiSessionMessageToolCallIdMetadataKey] ?? ''}'
          .trim();
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
    final toolRecordIds = <String>{
      for (final record in records)
        if (record.kind == _TrajectoryKind.tool ||
            record.kind == _TrajectoryKind.subtool)
          record.id,
    };
    return _TrajectorySnapshot(
      records: List<_TrajectoryRecord>.unmodifiable(records),
      turnIds: Set<int>.unmodifiable(turnIds),
      collapsibleTurnIds: Set<int>.unmodifiable(collapsibleTurnIds),
      toolRecordIds: Set<String>.unmodifiable(toolRecordIds),
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
  final timing = kind == _TrajectoryKind.user || kind == _TrajectoryKind.context
      ? (message.createdAt, 0)
      : _trajectoryTiming(message, kind);
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
  final callId = '${metadata[aiSessionMessageToolCallIdMetadataKey] ?? ''}'
      .trim();
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
  final callId = '${metadata[aiSessionMessageToolCallIdMetadataKey] ?? ''}'
      .trim();
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

double? _trajectoryMetadataDouble(
  Map<String, Object?> metadata,
  List<String> keys,
) {
  for (final key in keys) {
    final value = metadata[key];
    final parsed = value is num ? value.toDouble() : double.tryParse('$value');
    if (parsed != null && parsed.isFinite && parsed >= 0) return parsed;
  }
  return null;
}

List<double> _trajectoryMetadataNumberList(
  Map<String, Object?> metadata,
  String key,
) {
  final value = metadata[key];
  if (value is! List) return const <double>[];
  return List<double>.unmodifiable(
    value
        .map((item) => item is num ? item.toDouble() : double.tryParse('$item'))
        .whereType<double>()
        .where((item) => item.isFinite && item >= 0)
        .take(_kTrajectoryThroughputMaxPoints),
  );
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
    return openHandAmbientText(
      zh: '文件变更摘要',
      zhHant: '檔案變更摘要',
      en: 'File mutation summary',
      fr: 'Résumé des modifications de fichiers',
      de: 'Zusammenfassung der Dateiänderungen',
      ja: 'ファイル変更の概要',
    );
  }
  return '';
}

String _trajectoryToolPreview(
  String toolName,
  String arguments,
  String output,
) {
  final name = toolName.isEmpty
      ? openHandAmbientText(
          zh: '工具',
          zhHant: '工具',
          en: 'Tool',
          fr: 'Outil',
          de: 'Werkzeug',
          ja: 'ツール',
        )
      : toolName;
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
    final end = math.max(start, rawEnd - removedIdle);
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
      summaryKind = null,
      callRecordIds = const <String>[];

  const _TrajectoryLedgerRow.summary({
    required this.record,
    required this.summary,
    required this.summaryKind,
    this.callRecordIds = const <String>[],
  });

  final _TrajectoryRecord record;
  final String? summary;
  final String? summaryKind;
  final List<String> callRecordIds;
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
  final ScrollController _detailsScrollController = ScrollController();
  final Set<int> _collapsedTurns = <int>{};
  final Set<String> _collapsedCalls = <String>{};
  final Set<int> _callsVisibleInCollapsedTurns = <int>{};
  late final OpenHandDebouncer _refreshDebouncer = OpenHandDebouncer(
    delay: _kTrajectoryRefreshDelay,
  );
  bool _loadingInitial = true;
  bool _loadingOlder = false;
  bool _keepNewCallsCollapsed = false;
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_loadInitialWindow());
    });
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
    _detailsScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialWindow() async {
    AiSession? loaded;
    var failed = false;
    try {
      loaded = await widget.controller.ensureSessionMessageWindowHydrated(
        _session.id,
      );
    } catch (error, stack) {
      failed = true;
      silentLog('home_trajectory_dialog', '加载轨迹消息窗口', error, stack);
    }
    if (!mounted) return;
    final controllerError = widget.controller.sessionMessageWindowLoadErrorFor(
      _session.id,
    );
    final effective = failed || controllerError != null
        ? null
        : loaded ?? widget.controller.sessionById(_session.id);
    setState(() {
      _loadingInitial = false;
      if (effective == null) {
        _loadError = _trajectoryText(
          context,
          zh: '无法读取该线程的轨迹。',
          zhHant: '無法讀取該執行緒的軌跡。',
          en: 'Unable to load this thread trajectory.',
          fr: 'Impossible de charger la trajectoire de cette discussion.',
          de: 'Die Trajektorie dieses Threads kann nicht geladen werden.',
          ja: 'このスレッドの軌跡を読み込めません。',
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
    final callsWereExpanded = _allCallsExpanded;
    _session = session;
    _snapshot = _TrajectorySnapshot.fromSession(session);
    _collapsedTurns.removeWhere((turn) => !_snapshot.turnIds.contains(turn));
    _collapsedCalls.removeWhere((id) => !_snapshot.toolRecordIds.contains(id));
    if (_keepNewCallsCollapsed) {
      _collapsedCalls.addAll(_snapshot.toolRecordIds);
    }
    final turnsWithCalls = <int>{
      for (final record in _snapshot.records)
        if (_snapshot.toolRecordIds.contains(record.id)) record.turn,
    };
    _callsVisibleInCollapsedTurns.removeWhere(
      (turn) => !turnsWithCalls.contains(turn),
    );
    if (callsWereExpanded) {
      _callsVisibleInCollapsedTurns.addAll(
        turnsWithCalls.where(_collapsedTurns.contains),
      );
    }
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

  bool get _allCallsExpanded {
    if (_snapshot.toolRecordIds.isEmpty) return false;
    for (final record in _snapshot.records) {
      if (!_snapshot.toolRecordIds.contains(record.id)) continue;
      if (_collapsedCalls.contains(record.id) ||
          _collapsedTurns.contains(record.turn) &&
              !_callsVisibleInCollapsedTurns.contains(record.turn)) {
        return false;
      }
    }
    return true;
  }

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
        final visibleRecord = turnRecords.firstWhere(
          (item) => item.kind == _TrajectoryKind.user,
          orElse: () => turnRecords.first,
        );
        if (record.id != turnRecords.first.id) continue;
        rows.add(_TrajectoryLedgerRow.record(visibleRecord));
        final visibleCalls = _callsVisibleInCollapsedTurns.contains(record.turn)
            ? turnRecords
                  .where(
                    (item) =>
                        item.id != visibleRecord.id &&
                        _snapshot.toolRecordIds.contains(item.id) &&
                        !_collapsedCalls.contains(item.id),
                  )
                  .toList(growable: false)
            : const <_TrajectoryRecord>[];
        final visibleCallIds = visibleCalls.map((item) => item.id).toSet();
        final hiddenRecords = turnRecords
            .where(
              (item) =>
                  item.id != visibleRecord.id &&
                  !visibleCallIds.contains(item.id),
            )
            .toList(growable: false);
        if (hiddenRecords.isNotEmpty) {
          final steps = hiddenRecords
              .map((item) => item.step)
              .where((item) => item > 0)
              .toSet();
          final calls = hiddenRecords
              .where((item) => _snapshot.toolRecordIds.contains(item.id))
              .length;
          final stepSummary =
              '${steps.length} ${openHandAmbientText(zh: '步', zhHant: '步', en: steps.length == 1 ? 'step' : 'steps', fr: steps.length == 1 ? 'étape' : 'étapes', de: steps.length == 1 ? 'Schritt' : 'Schritte', ja: 'ステップ')}';
          final summary = calls == 0
              ? stepSummary
              : '$stepSummary · $calls ${openHandAmbientText(zh: '工具调用', zhHant: '工具呼叫', en: calls == 1 ? 'tool call' : 'tool calls', fr: calls == 1 ? 'appel d’outil' : 'appels d’outil', de: calls == 1 ? 'Werkzeugaufruf' : 'Werkzeugaufrufe', ja: 'ツール呼び出し')}';
          rows.add(
            _TrajectoryLedgerRow.summary(
              record: visibleRecord,
              summary: summary,
              summaryKind: 'turn',
            ),
          );
        }
        rows.addAll(visibleCalls.map(_TrajectoryLedgerRow.record));
        index += turnRecords.length - 1;
        continue;
      }

      final recordIsCall = _snapshot.toolRecordIds.contains(record.id);
      var next = recordIsCall ? index : index + 1;
      final calls = <_TrajectoryRecord>[];
      while (next < filtered.length) {
        final candidate = filtered[next];
        if (candidate.turn != record.turn || candidate.step != record.step) {
          break;
        }
        if (!_snapshot.toolRecordIds.contains(candidate.id)) break;
        calls.add(candidate);
        next += 1;
      }
      if (!recordIsCall) rows.add(_TrajectoryLedgerRow.record(record));
      final runCollapsed =
          calls.isNotEmpty &&
          calls.every((call) => _collapsedCalls.contains(call.id));
      if (!runCollapsed) {
        if (recordIsCall) rows.add(_TrajectoryLedgerRow.record(record));
        continue;
      }
      final names = calls
          .map((call) => call.toolName ?? 'tool')
          .toSet()
          .join(', ');
      rows.add(
        _TrajectoryLedgerRow.summary(
          record: record,
          summary:
              '${calls.length} ${openHandAmbientText(zh: '工具调用', zhHant: '工具呼叫', en: calls.length == 1 ? 'tool call' : 'tool calls', fr: calls.length == 1 ? 'appel d’outil' : 'appels d’outil', de: calls.length == 1 ? 'Werkzeugaufruf' : 'Werkzeugaufrufe', ja: 'ツール呼び出し')} · $names',
          summaryKind: 'calls',
          callRecordIds: calls.map((call) => call.id).toList(growable: false),
        ),
      );
      index = next - 1;
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
      _activeDetailTab = _trajectoryDetailTabKeys(record).first;
    });
    _resetDetailsScrollPosition();
    final messageId = record.sourceMessageId;
    if (messageId == null) return;
    final generation = ++_metadataLoadGeneration;
    setState(() => _selectedMetadataLoading = true);
    unawaited(widget.controller
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
        }));
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
          curve: kOpenHandSwitchInCurve,
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

  void _resetDetailsScrollPosition() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_detailsScrollController.hasClients) return;
      _detailsScrollController.jumpTo(0);
    });
  }

  void _toggleAllTurns() {
    final collapsible = _collapsibleTurns;
    final allCollapsed =
        collapsible.isNotEmpty && collapsible.every(_collapsedTurns.contains);
    setState(() {
      _callsVisibleInCollapsedTurns.clear();
      if (allCollapsed) {
        _collapsedTurns.removeAll(collapsible);
      } else {
        _collapsedTurns.addAll(collapsible);
      }
    });
  }

  void _toggleTurn(int turn) {
    if (!_collapsibleTurns.contains(turn)) return;
    setState(() {
      _callsVisibleInCollapsedTurns.remove(turn);
      if (!_collapsedTurns.remove(turn)) {
        _collapsedTurns.add(turn);
      }
    });
  }

  void _toggleAllCalls() {
    final expand = !_allCallsExpanded;
    setState(() {
      _keepNewCallsCollapsed = !expand;
      if (expand) {
        _collapsedCalls.removeAll(_snapshot.toolRecordIds);
        _callsVisibleInCollapsedTurns.addAll(<int>{
          for (final record in _snapshot.records)
            if (_snapshot.toolRecordIds.contains(record.id) &&
                _collapsedTurns.contains(record.turn))
              record.turn,
        });
      } else {
        _collapsedCalls.addAll(_snapshot.toolRecordIds);
        _callsVisibleInCollapsedTurns.clear();
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
    final messageRangeEnd =
        _session.messageWindowStartIndex + _session.messages.length;
    final messageRangeTotal = math.max(
      _session.messageTotalCount,
      messageRangeEnd,
    );
    final messageRangeLabel = _loadingInitial
        ? null
        : _session.messages.isEmpty
        ? '0 / $messageRangeTotal'
        : '${_session.messageWindowStartIndex + 1}-$messageRangeEnd / '
              '$messageRangeTotal';
    const radius = kOpenHandBorderRadius18;
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
              allCallsExpanded: _allCallsExpanded,
              searchController: _searchController,
              rangeLabel: messageRangeLabel,
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
      constraints: const BoxConstraints(minHeight: 70),
      padding: const EdgeInsets.fromLTRB(18, 12, 10, 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Container(
            width: _kTrajectoryHeaderIconSize,
            height: _kTrajectoryHeaderIconSize,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: kOpenHandBorderRadius8,
              border: Border.all(
                color: colorScheme.primary.withValues(alpha: 0.35),
              ),
            ),
            child: Icon(
              Icons.route_rounded,
              size: 23,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
          kOpenHandHGap12,
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  openHandTrajectoryLabel(context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  _session.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          kOpenHandHGap12,
          _TrajectoryCloseButton(
            tooltip: openHandCloseLabel(context),
            onPressed: () => Navigator.of(context).pop(),
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
              _trajectoryText(
                context,
                zh: '正在装配轨迹…',
                zhHant: '正在組裝軌跡…',
                en: 'Assembling trajectory…',
                fr: 'Assemblage de la trajectoire…',
                de: 'Trajektorie wird zusammengestellt…',
                ja: '軌跡を構築中…',
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
          actionLabel: _trajectoryText(
            context,
            zh: '重试',
            zhHant: '重試',
            en: 'Retry',
            fr: 'Réessayer',
            de: 'Erneut versuchen',
            ja: '再試行',
          ),
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
          title: _trajectoryText(
            context,
            zh: '此线程暂无可展示的轨迹',
            zhHant: '此執行緒暫無可展示的軌跡',
            en: 'No trajectory is available for this thread',
            fr: 'Aucune trajectoire disponible pour cette discussion',
            de: 'Für diesen Thread ist keine Trajektorie verfügbar',
            ja: 'このスレッドに表示できる軌跡はありません',
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
                onTabChanged: (tab) {
                  if (tab == _activeDetailTab) return;
                  setState(() => _activeDetailTab = tab);
                  _resetDetailsScrollPosition();
                },
                onClose: _closeDetails,
                scrollController: _detailsScrollController,
              );
        final ledger = _buildLedger(context);
        if (!desktop) {
          final motion = openHandMotionDuration(context, kOpenHandMotion220);
          final detailsHeight = math.min(360.0, constraints.maxHeight * 0.48);
          return Column(
            children: [
              Expanded(child: ledger),
              AnimatedContainer(
                duration: motion,
                curve: kOpenHandSwitchInCurve,
                height: details == null ? 0 : detailsHeight,
                decoration: BoxDecoration(
                  border: details == null
                      ? null
                      : Border(
                          top: BorderSide(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                ),
                child: details == null
                    ? const SizedBox.shrink()
                    : ClipRect(
                        child: OverflowBox(
                          alignment: Alignment.bottomCenter,
                          minHeight: detailsHeight,
                          maxHeight: detailsHeight,
                          child: details,
                        ),
                      ),
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
              curve: kOpenHandSwitchInCurve,
              width: details == null ? 0 : _detailsWidth,
              child: details == null
                  ? const SizedBox.shrink()
                  : ClipRect(
                      child: OverflowBox(
                        alignment: Alignment.centerRight,
                        minWidth: _detailsWidth,
                        maxWidth: _detailsWidth,
                        child: Row(
                          children: [
                            MouseRegion(
                              cursor: SystemMouseCursors.resizeColumn,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onHorizontalDragUpdate: (details) {
                                  setState(() {
                                    _detailsWidth =
                                        (_detailsWidth - details.delta.dx)
                                            .clamp(
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
          title: _trajectoryText(
            context,
            zh: '没有匹配的轨迹记录',
            zhHant: '沒有符合的軌跡記錄',
            en: 'No trajectory records match',
            fr: 'Aucun enregistrement de trajectoire correspondant',
            de: 'Keine passenden Trajektorien-Datensätze',
            ja: '一致する軌跡レコードはありません',
          ),
          actionLabel: _searchQuery.isEmpty
              ? null
              : _trajectoryText(
                  context,
                  zh: '清除搜索',
                  zhHant: '清除搜尋',
                  en: 'Clear search',
                  fr: 'Effacer la recherche',
                  de: 'Suche löschen',
                  ja: '検索をクリア',
                ),
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
                      onDoublePressed:
                          row.summary == null &&
                              row.record.kind == _TrajectoryKind.user &&
                              _collapsibleTurns.contains(row.record.turn)
                          ? () {
                              _selectRecord(row.record);
                              _toggleTurn(row.record.turn);
                            }
                          : null,
                      onPressed: row.summary == null
                          ? () => _selectRecord(row.record)
                          : row.summaryKind == 'turn'
                          ? () => _toggleTurn(row.record.turn)
                          : () {
                              setState(() {
                                _keepNewCallsCollapsed = false;
                                _collapsedCalls.removeAll(row.callRecordIds);
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
    required this.allCallsExpanded,
    required this.searchController,
    required this.rangeLabel,
    required this.onDurationChanged,
    required this.onToggleTurns,
    required this.onToggleCalls,
  });

  final bool actualDuration;
  final bool allTurnsCollapsed;
  final bool allCallsExpanded;
  final TextEditingController searchController;
  final String? rangeLabel;
  final VoidCallback onDurationChanged;
  final VoidCallback onToggleTurns;
  final VoidCallback onToggleCalls;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: _kTrajectoryToolbarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 700;
          final searchBorder = OutlineInputBorder(
            borderRadius: kOpenHandBorderRadius10,
            borderSide: BorderSide(color: colorScheme.outlineVariant),
          );
          return Row(
            children: [
              _TrajectoryToolbarButton(
                icon: Icons.schedule_outlined,
                label: compact
                    ? null
                    : _trajectoryText(
                        context,
                        zh: '时长',
                        zhHant: '時長',
                        en: 'Duration',
                        fr: 'Durée',
                        de: 'Dauer',
                        ja: '所要時間',
                      ),
                selected: actualDuration,
                tooltip: _trajectoryText(
                  context,
                  zh: actualDuration ? '使用等宽记录' : '使用实际耗时',
                  zhHant: actualDuration ? '使用等寬記錄' : '使用實際耗時',
                  en: actualDuration
                      ? 'Use equal-width records'
                      : 'Use actual duration',
                  fr: actualDuration
                      ? 'Utiliser des enregistrements de largeur égale'
                      : 'Utiliser la durée réelle',
                  de: actualDuration
                      ? 'Datensätze mit gleicher Breite verwenden'
                      : 'Tatsächliche Dauer verwenden',
                  ja: actualDuration ? '等幅レコードを使用' : '実際の所要時間を使用',
                ),
                onPressed: onDurationChanged,
              ),
              _TrajectoryToolbarButton(
                icon: allTurnsCollapsed
                    ? Icons.add_box_outlined
                    : Icons.indeterminate_check_box_outlined,
                label: compact
                    ? null
                    : _trajectoryText(
                        context,
                        zh: '轮次',
                        zhHant: '輪次',
                        en: 'Turns',
                        fr: 'Tours',
                        de: 'Durchläufe',
                        ja: 'ターン',
                      ),
                tooltip: _trajectoryText(
                  context,
                  zh: allTurnsCollapsed ? '展开轮次' : '折叠轮次',
                  zhHant: allTurnsCollapsed ? '展開輪次' : '摺疊輪次',
                  en: allTurnsCollapsed ? 'Expand turns' : 'Collapse turns',
                  fr: allTurnsCollapsed
                      ? 'Développer les tours'
                      : 'Réduire les tours',
                  de: allTurnsCollapsed
                      ? 'Durchläufe einblenden'
                      : 'Durchläufe einklappen',
                  ja: allTurnsCollapsed ? 'ターンを展開' : 'ターンを折りたたむ',
                ),
                onPressed: onToggleTurns,
              ),
              _TrajectoryToolbarButton(
                icon: allCallsExpanded
                    ? Icons.indeterminate_check_box_outlined
                    : Icons.add_box_outlined,
                label: compact
                    ? null
                    : _trajectoryText(
                        context,
                        zh: '调用',
                        zhHant: '呼叫',
                        en: 'Calls',
                        fr: 'Appels',
                        de: 'Aufrufe',
                        ja: '呼び出し',
                      ),
                tooltip: _trajectoryText(
                  context,
                  zh: allCallsExpanded ? '折叠调用' : '展开调用',
                  zhHant: allCallsExpanded ? '摺疊呼叫' : '展開呼叫',
                  en: allCallsExpanded ? 'Collapse calls' : 'Expand calls',
                  fr: allCallsExpanded
                      ? 'Réduire les appels'
                      : 'Développer les appels',
                  de: allCallsExpanded
                      ? 'Aufrufe einklappen'
                      : 'Aufrufe einblenden',
                  ja: allCallsExpanded ? '呼び出しを折りたたむ' : '呼び出しを展開',
                ),
                onPressed: onToggleCalls,
              ),
              const Spacer(),
              if (rangeLabel != null) ...[
                Container(
                  width: compact ? 78 : null,
                  height: _kTrajectoryToolbarControlHeight,
                  constraints: compact
                      ? null
                      : const BoxConstraints(minWidth: 88),
                  padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainer,
                    border: Border.all(color: colorScheme.outlineVariant),
                    borderRadius: kOpenHandBorderRadius10,
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      rangeLabel!,
                      maxLines: 1,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                kOpenHandHGap6,
              ],
              SizedBox(
                width: compact ? 116 : 220,
                height: _kTrajectoryToolbarControlHeight,
                child: TextField(
                  controller: searchController,
                  textAlignVertical: TextAlignVertical.center,
                  cursorHeight: 18,
                  style: Theme.of(context).textTheme.bodySmall,
                  decoration: InputDecoration(
                    constraints: const BoxConstraints.tightFor(
                      height: _kTrajectoryToolbarControlHeight,
                    ),
                    isCollapsed: true,
                    hintText: _trajectoryText(
                      context,
                      zh: '搜索',
                      zhHant: '搜尋',
                      en: 'Search',
                      fr: 'Rechercher',
                      de: 'Suchen',
                      ja: '検索',
                    ),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      size: 18,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 30,
                      maxWidth: 30,
                      minHeight: _kTrajectoryToolbarControlHeight,
                      maxHeight: _kTrajectoryToolbarControlHeight,
                    ),
                    suffixIcon: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: searchController,
                      builder: (context, value, _) => value.text.isEmpty
                          ? const SizedBox.shrink()
                          : IconButton(
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                overlayColor: Colors.transparent,
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                padding: EdgeInsets.zero,
                              ),
                              constraints: const BoxConstraints.tightFor(
                                width: 28,
                                height: 28,
                              ),
                              tooltip: _trajectoryText(
                                context,
                                zh: '清除搜索',
                                zhHant: '清除搜尋',
                                en: 'Clear search',
                                fr: 'Effacer la recherche',
                                de: 'Suche löschen',
                                ja: '検索をクリア',
                              ),
                              onPressed: searchController.clear,
                              icon: const Icon(Icons.close_rounded, size: 15),
                            ),
                    ),
                    suffixIconConstraints: const BoxConstraints(
                      minWidth: 32,
                      maxWidth: 32,
                      minHeight: _kTrajectoryToolbarControlHeight,
                      maxHeight: _kTrajectoryToolbarControlHeight,
                    ),
                    filled: true,
                    fillColor: colorScheme.surfaceContainer,
                    contentPadding: const EdgeInsetsDirectional.only(end: 4),
                    border: searchBorder,
                    enabledBorder: searchBorder,
                    focusedBorder: searchBorder.copyWith(
                      borderSide: BorderSide(
                        color: colorScheme.primary.withValues(alpha: 0.78),
                        width: 1.5,
                      ),
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
              height: _kTrajectoryToolbarControlHeight,
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

class _TrajectoryCloseButton extends StatelessWidget {
  const _TrajectoryCloseButton({
    required this.tooltip,
    required this.onPressed,
    this.size = _kTrajectoryHeaderActionSize,
    this.iconSize = 20,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return IconButton(
      constraints: BoxConstraints.tightFor(width: size, height: size),
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        foregroundColor: colorScheme.onSurfaceVariant,
        backgroundColor: colorScheme.surfaceContainerHighest,
        hoverColor: colorScheme.primary.withValues(alpha: 0.08),
        focusColor: colorScheme.primary.withValues(alpha: 0.08),
        highlightColor: colorScheme.primary.withValues(alpha: 0.12),
        shape: const RoundedRectangleBorder(
          borderRadius: kOpenHandBorderRadius8,
        ),
      ),
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(Icons.close_rounded, size: iconSize),
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
        color: colorScheme.surfaceContainerLowest,
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
                    _trajectoryText(
                      context,
                      zh: '输入',
                      zhHant: '輸入',
                      en: 'Input',
                      fr: 'Entrée',
                      de: 'Eingabe',
                      ja: '入力',
                    ),
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
                    _trajectoryText(
                      context,
                      zh: '模型',
                      zhHant: '模型',
                      en: 'Model',
                      fr: 'Modèle',
                      de: 'Modell',
                      ja: 'モデル',
                    ),
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
                    _trajectoryText(
                      context,
                      zh: '工具',
                      zhHant: '工具',
                      en: 'Tools',
                      fr: 'Outils',
                      de: 'Werkzeuge',
                      ja: 'ツール',
                    ),
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
                            emptyLabel: _trajectoryText(
                              context,
                              zh: '暂无时间数据',
                              zhHant: '暫無時間資料',
                              en: 'No timing data',
                              fr: 'Aucune donnée temporelle',
                              de: 'Keine Zeitdaten',
                              ja: '時間データなし',
                            ),
                            colorScheme: colorScheme,
                          ),
                        ),
                        if (widget.hasEarlierRecords)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Tooltip(
                              message: _trajectoryText(
                                context,
                                zh: '加载更早轨迹',
                                zhHant: '載入較早軌跡',
                                en: 'Load earlier trajectory',
                                fr: 'Charger la trajectoire précédente',
                                de: 'Frühere Trajektorie laden',
                                ja: '以前の軌跡を読み込む',
                              ),
                              child: InkWell(
                                onTap: widget.loadingEarlier
                                    ? null
                                    : widget.onLoadEarlier,
                                child: Container(
                                  width: 28,
                                  alignment: Alignment.center,
                                  color: colorScheme.surfaceContainerLowest
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
    required this.emptyLabel,
    required this.colorScheme,
  });

  final _TrajectoryProjection projection;
  final double domainStart;
  final double domainEnd;
  final _TrajectoryRange? selection;
  final Set<String>? searchMatches;
  final String? selectedRecordId;
  final String? hoveredRecordId;
  final String emptyLabel;
  final ColorScheme colorScheme;

  double _x(double value, double width) =>
      (value - domainStart) / math.max(1, domainEnd - domainStart) * width;

  @override
  void paint(Canvas canvas, Size size) {
    final timelineColors = colorScheme.brightness == Brightness.dark
        ? _kTrajectoryTimelineDarkColors
        : _kTrajectoryTimelineLightColors;
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
        ..color = timelineColors.user.withValues(alpha: 0.12);
      canvas.drawRect(
        Rect.fromLTRB(left, 0, right, size.height),
        selectedPaint,
      );
      final edgePaint = Paint()
        ..color = timelineColors.user
        ..strokeWidth = 2;
      canvas.drawLine(Offset(left, 0), Offset(left, size.height), edgePaint);
      canvas.drawLine(Offset(right, 0), Offset(right, size.height), edgePaint);
    }
    for (final span in projection.spans) {
      if (span.end < domainStart || span.start > domainEnd) continue;
      var opacity = switch (span.record.kind) {
        _TrajectoryKind.assistant ||
        _TrajectoryKind.compacted ||
        _TrajectoryKind.tool ||
        _TrajectoryKind.subtool => 1.0,
        _ => 0.78,
      };
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
          ? timelineColors.error
          : _trajectoryTimelineKindColor(timelineColors, span.record.kind);
      canvas.drawRRect(rect, Paint()..color = color.withValues(alpha: opacity));
      if (span.record.id == selectedRecordId ||
          span.record.id == hoveredRecordId) {
        final outline = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = timelineColors.user;
        canvas.drawRRect(rect.inflate(2), outline);
      }
    }
    if (projection.spans.isEmpty) {
      final painter = TextPainter(
        text: TextSpan(
          text: emptyLabel,
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
        oldDelegate.emptyLabel != emptyLabel ||
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
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: TextButton.icon(
        onPressed: loading ? null : onPressed,
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          foregroundColor: colorScheme.primary,
          backgroundColor: colorScheme.primaryContainer.withValues(alpha: 0.42),
          disabledForegroundColor: colorScheme.onSurfaceVariant,
          disabledBackgroundColor: colorScheme.surfaceContainerHighest,
          shape: const RoundedRectangleBorder(borderRadius: kOpenHandBorderRadius8),
        ),
        icon: loading
            ? SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 1.8,
                  color: colorScheme.primary,
                ),
              )
            : const Icon(Icons.more_horiz_rounded, size: 18),
        label: Text(
          loading
              ? _trajectoryText(
                  context,
                  zh: '正在加载更早轨迹…',
                  zhHant: '正在載入較早軌跡…',
                  en: 'Loading earlier trajectory…',
                  fr: 'Chargement de la trajectoire précédente…',
                  de: 'Frühere Trajektorie wird geladen…',
                  ja: '以前の軌跡を読み込み中…',
                )
              : _trajectoryText(
                  context,
                  zh: '加载更早轨迹',
                  zhHant: '載入較早軌跡',
                  en: 'Load earlier trajectory',
                  fr: 'Charger la trajectoire précédente',
                  de: 'Frühere Trajektorie laden',
                  ja: '以前の軌跡を読み込む',
                ),
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
    this.onDoublePressed,
  });

  final _TrajectoryLedgerRow row;
  final bool isTurnStart;
  final bool isStepStart;
  final bool selected;
  final VoidCallback onPressed;
  final VoidCallback? onDoublePressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final record = row.record;
    final accent = record.isError
        ? colorScheme.error
        : _trajectoryKindColor(colorScheme, record.kind);
    final summary = row.summary;
    return Material(
      color: selected
          ? colorScheme.primary.withValues(alpha: 0.08)
          : Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        onDoubleTap: onDoublePressed,
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
                              ? _trajectoryText(
                                  context,
                                  zh: '请求 #${record.requestNumber}',
                                  zhHant: '請求 #${record.requestNumber}',
                                  en: 'Request #${record.requestNumber}',
                                  fr: 'Requête n° ${record.requestNumber}',
                                  de: 'Anfrage #${record.requestNumber}',
                                  ja: 'リクエスト #${record.requestNumber}',
                                )
                              : _trajectoryText(
                                  context,
                                  zh: '步骤 ${record.step}',
                                  zhHant: '步驟 ${record.step}',
                                  en: 'Step ${record.step}',
                                  fr: 'Étape ${record.step}',
                                  de: 'Schritt ${record.step}',
                                  ja: 'ステップ ${record.step}',
                                ),
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
                            borderRadius: kOpenHandBorderRadius3,
                          ),
                          child: Text(
                            _trajectoryText(
                              context,
                              zh: '轮次 ${record.turn}',
                              zhHant: '輪次 ${record.turn}',
                              en: 'Turn ${record.turn}',
                              fr: 'Tour ${record.turn}',
                              de: 'Durchlauf ${record.turn}',
                              ja: 'ターン ${record.turn}',
                            ),
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
                                  ? _trajectoryText(
                                      context,
                                      zh: '无内容',
                                      zhHant: '無內容',
                                      en: 'No content',
                                      fr: 'Aucun contenu',
                                      de: 'Kein Inhalt',
                                      ja: '内容なし',
                                    )
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
                          ? colorScheme.error
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
    final colorScheme = Theme.of(context).colorScheme;
    final accent = record.isError
        ? colorScheme.error
        : _trajectoryKindColor(colorScheme, record.kind);
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
              _trajectoryKindLabel(context, record.kind),
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

Color _trajectoryKindColor(ColorScheme colorScheme, _TrajectoryKind kind) =>
    switch (kind) {
      _TrajectoryKind.system => colorScheme.onSurfaceVariant,
      _TrajectoryKind.user => colorScheme.primary,
      _TrajectoryKind.context => colorScheme.secondary,
      _TrajectoryKind.compacted => colorScheme.outline,
      _TrajectoryKind.assistant => colorScheme.tertiary,
      _TrajectoryKind.tool || _TrajectoryKind.subtool => Color.lerp(
        colorScheme.primary,
        colorScheme.tertiary,
        0.42,
      )!,
    };

Color _trajectoryTimelineKindColor(
  ({
    Color system,
    Color user,
    Color context,
    Color assistant,
    Color tool,
    Color error,
  })
  colors,
  _TrajectoryKind kind,
) => switch (kind) {
  _TrajectoryKind.system => colors.system,
  _TrajectoryKind.user => colors.user,
  _TrajectoryKind.context => colors.context,
  _TrajectoryKind.compacted || _TrajectoryKind.assistant => colors.assistant,
  _TrajectoryKind.tool || _TrajectoryKind.subtool => colors.tool,
};

IconData _trajectoryKindIcon(_TrajectoryKind kind) => switch (kind) {
  _TrajectoryKind.system => Icons.settings_outlined,
  _TrajectoryKind.user => Icons.person_outline_rounded,
  _TrajectoryKind.context => Icons.info_outline_rounded,
  _TrajectoryKind.compacted => Icons.compress_rounded,
  _TrajectoryKind.assistant => Icons.auto_awesome_outlined,
  _TrajectoryKind.tool || _TrajectoryKind.subtool => Icons.build_outlined,
};

String _trajectoryKindLabel(BuildContext context, _TrajectoryKind kind) =>
    switch (kind) {
      _TrajectoryKind.system => _trajectoryText(
        context,
        zh: '系统',
        zhHant: '系統',
        en: 'SYSTEM',
        fr: 'SYSTÈME',
        de: 'SYSTEM',
        ja: 'システム',
      ),
      _TrajectoryKind.user => _trajectoryText(
        context,
        zh: '用户',
        zhHant: '使用者',
        en: 'USER',
        fr: 'UTILISATEUR',
        de: 'BENUTZER',
        ja: 'ユーザー',
      ),
      _TrajectoryKind.context => _trajectoryText(
        context,
        zh: '上下文',
        zhHant: '上下文',
        en: 'CONTEXT',
        fr: 'CONTEXTE',
        de: 'KONTEXT',
        ja: 'コンテキスト',
      ),
      _TrajectoryKind.compacted => _trajectoryText(
        context,
        zh: '已压缩',
        zhHant: '已壓縮',
        en: 'COMPACTED',
        fr: 'COMPACTÉ',
        de: 'KOMPRIMIERT',
        ja: '圧縮済み',
      ),
      _TrajectoryKind.assistant => _trajectoryText(
        context,
        zh: '助手',
        zhHant: '助理',
        en: 'ASSISTANT',
        fr: 'ASSISTANT',
        de: 'ASSISTENT',
        ja: 'アシスタント',
      ),
      _TrajectoryKind.tool || _TrajectoryKind.subtool => _trajectoryText(
        context,
        zh: '工具',
        zhHant: '工具',
        en: kind == _TrajectoryKind.subtool ? 'SUBTOOL' : 'TOOL',
        fr: kind == _TrajectoryKind.subtool ? 'SOUS-OUTIL' : 'OUTIL',
        de: kind == _TrajectoryKind.subtool ? 'UNTERWERKZEUG' : 'WERKZEUG',
        ja: kind == _TrajectoryKind.subtool ? 'サブツール' : 'ツール',
      ),
    };

String _trajectoryDurationLabel(int? milliseconds) {
  if (milliseconds == null) return '—';
  if (milliseconds < 1000) return '$milliseconds ms';
  final seconds = milliseconds / 1000;
  return '${seconds.toStringAsFixed(seconds < 10 ? 2 : 1)} s';
}

List<String> _trajectoryDetailTabKeys(_TrajectoryRecord record) {
  return switch (record.kind) {
    _TrajectoryKind.system => const <String>['system-prompt', 'tools'],
    _TrajectoryKind.user || _TrajectoryKind.context => const <String>[
      'summary',
      'rendered',
      'raw',
      'source',
      'timing',
    ],
    _TrajectoryKind.assistant => const <String>[
      'summary',
      'rendered',
      'raw',
      'options',
      'usage',
      'timing',
    ],
    _TrajectoryKind.compacted => const <String>['summary', 'raw'],
    _TrajectoryKind.tool || _TrajectoryKind.subtool => const <String>[
      'summary',
      'input',
      'output',
      'schema',
      'timing',
    ],
  };
}

List<(String, String)> _trajectoryDetailTabs(
  BuildContext context,
  _TrajectoryRecord record,
) {
  final labels = <String, String>{
    'system-prompt': _trajectoryText(
      context,
      zh: '系统提示词',
      zhHant: '系統提示詞',
      en: 'System Prompt',
      fr: 'Prompt système',
      de: 'System-Prompt',
      ja: 'システムプロンプト',
    ),
    'tools': _trajectoryText(
      context,
      zh: '工具',
      zhHant: '工具',
      en: 'Tools',
      fr: 'Outils',
      de: 'Werkzeuge',
      ja: 'ツール',
    ),
    'summary': _trajectoryText(
      context,
      zh: '摘要',
      zhHant: '摘要',
      en: 'Summary',
      fr: 'Résumé',
      de: 'Zusammenfassung',
      ja: '概要',
    ),
    'rendered': _trajectoryText(
      context,
      zh: '渲染内容',
      zhHant: '渲染內容',
      en: 'Rendered',
      fr: 'Rendu',
      de: 'Gerendert',
      ja: '表示',
    ),
    'raw': _trajectoryText(
      context,
      zh: '原始内容',
      zhHant: '原始內容',
      en: 'Raw',
      fr: 'Brut',
      de: 'Roh',
      ja: 'Raw',
    ),
    'source': _trajectoryText(
      context,
      zh: '来源',
      zhHant: '來源',
      en: 'Source',
      fr: 'Source',
      de: 'Quelle',
      ja: 'ソース',
    ),
    'options': _trajectoryText(
      context,
      zh: '选项',
      zhHant: '選項',
      en: 'Options',
      fr: 'Options',
      de: 'Optionen',
      ja: '設定',
    ),
    'usage': _trajectoryText(
      context,
      zh: '用量',
      zhHant: '用量',
      en: 'Usage',
      fr: 'Utilisation',
      de: 'Verbrauch',
      ja: '使用量',
    ),
    'timing': _trajectoryText(
      context,
      zh: '耗时',
      zhHant: '耗時',
      en: 'Timing',
      fr: 'Temps',
      de: 'Zeit',
      ja: '時間',
    ),
    'input': _trajectoryText(
      context,
      zh: '输入',
      zhHant: '輸入',
      en: 'Input',
      fr: 'Entrée',
      de: 'Eingabe',
      ja: '入力',
    ),
    'output': _trajectoryText(
      context,
      zh: '输出',
      zhHant: '輸出',
      en: 'Output',
      fr: 'Sortie',
      de: 'Ausgabe',
      ja: '出力',
    ),
    'schema': _trajectoryText(
      context,
      zh: '结构',
      zhHant: '結構',
      en: 'Schema',
      fr: 'Schéma',
      de: 'Schema',
      ja: 'スキーマ',
    ),
  };
  return [
    for (final key in _trajectoryDetailTabKeys(record))
      (key, labels[key] ?? key),
  ];
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
    required this.scrollController,
  });

  final _TrajectoryRecord record;
  final Map<String, Object?> metadata;
  final bool metadataLoading;
  final String activeTab;
  final ValueChanged<String> onTabChanged;
  final VoidCallback onClose;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = record.isError
        ? colorScheme.error
        : _trajectoryKindColor(colorScheme, record.kind);
    final infoAccent = record.kind == _TrajectoryKind.system
        ? colorScheme.primary
        : accent;
    final infoText = record.turn > 0
        ? _trajectoryText(
            context,
            zh: '轮次 ${record.turn} · 步骤 ${record.step}',
            zhHant: '輪次 ${record.turn} · 步驟 ${record.step}',
            en: 'Turn ${record.turn} · Step ${record.step}',
            fr: 'Tour ${record.turn} · Étape ${record.step}',
            de: 'Durchlauf ${record.turn} · Schritt ${record.step}',
            ja: 'ターン ${record.turn} · ステップ ${record.step}',
          )
        : record.preview;
    final tabs = _trajectoryDetailTabs(context, record);
    final effectiveTab = tabs.any((tab) => tab.$1 == activeTab)
        ? activeTab
        : tabs.first.$1;
    final selectedTabIndex = tabs.indexWhere((tab) => tab.$1 == effectiveTab);
    final visualTabIndex = Directionality.of(context) == TextDirection.rtl
        ? tabs.length - selectedTabIndex - 1
        : selectedTabIndex;
    final tabMotion = cardMotionDurationFor(context, expanding: true);
    final indicatorAlignment = tabs.length == 1
        ? Alignment.bottomCenter
        : Alignment(-1 + visualTabIndex * 2 / (tabs.length - 1), 1);
    return ColoredBox(
      color: colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 44,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  _TrajectoryKindTag(record: record),
                  kOpenHandHGap8,
                  Expanded(
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: AnimatedContainer(
                        duration: tabMotion,
                        curve: kCardDecorationMotionCurve,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: infoAccent.withValues(alpha: 0.15),
                          borderRadius: kOpenHandBorderRadius5,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              record.turn > 0
                                  ? Icons.route_outlined
                                  : Icons.description_outlined,
                              size: 13,
                              color: infoAccent,
                            ),
                            kOpenHandHGap5,
                            Container(
                              width: 1,
                              height: 13,
                              color: infoAccent.withValues(alpha: 0.3),
                            ),
                            kOpenHandHGap5,
                            Flexible(
                              child: Text(
                                infoText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: infoAccent,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0,
                                ),
                              ),
                            ),
                          ],
                        ),
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
                  _TrajectoryCloseButton(
                    size: _kTrajectoryDetailsActionSize,
                    iconSize: _kTrajectoryDetailsActionIconSize,
                    tooltip: _trajectoryText(
                      context,
                      zh: '关闭详情',
                      zhHant: '關閉詳情',
                      en: 'Close details',
                      fr: 'Fermer les détails',
                      de: 'Details schließen',
                      ja: '詳細を閉じる',
                    ),
                    onPressed: onClose,
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            height: 38,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Row(
                    children: [
                      for (final tab in tabs)
                        Expanded(
                          child: _TrajectoryDetailTab(
                            label: tab.$2,
                            selected: tab.$1 == effectiveTab,
                            onPressed: () => onTabChanged(tab.$1),
                          ),
                        ),
                    ],
                  ),
                  IgnorePointer(
                    child: AnimatedAlign(
                      duration: tabMotion,
                      curve: kCardMotionCurve,
                      alignment: indicatorAlignment,
                      child: FractionallySizedBox(
                        widthFactor: 1 / tabs.length,
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            height: 2,
                            margin: const EdgeInsets.symmetric(horizontal: 6),
                            decoration: BoxDecoration(
                              color: colorScheme.primary,
                              borderRadius: kOpenHandPillBorderRadius,
                            ),
                          ),
                        ),
                      ),
                    ),
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
              scrollController: scrollController,
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final duration = cardMotionDurationFor(context, expanding: selected);
    final style = theme.textTheme.labelSmall?.copyWith(
      color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
    );
    return InkWell(
      onTap: onPressed,
      borderRadius: kOpenHandBorderRadius5,
      child: SizedBox(
        height: 38,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: AnimatedDefaultTextStyle(
                duration: duration,
                curve: kCardDecorationMotionCurve,
                style: style ?? const TextStyle(),
                child: Text(label, maxLines: 1),
              ),
            ),
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
    required this.scrollController,
  });

  final _TrajectoryRecord record;
  final Map<String, Object?> metadata;
  final String activeTab;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final content = switch (activeTab) {
      'summary' => _buildSummary(context),
      'system-prompt' => _TrajectoryMarkdownDetail(
        text: _trajectorySystemPrompt(metadata),
        emptyText: _trajectoryText(
          context,
          zh: '本次请求未记录系统提示词',
          zhHant: '本次請求未記錄系統提示詞',
          en: 'No system prompt in this request',
          fr: 'Aucun prompt système enregistré pour cette requête',
          de: 'Für diese Anfrage wurde kein System-Prompt aufgezeichnet',
          ja: 'このリクエストにはシステムプロンプトが記録されていません',
        ),
      ),
      'tools' => _TrajectoryStructuredDetail(
        text: _trajectoryToolCatalog(metadata),
        emptyText: _trajectoryText(
          context,
          zh: '本次请求未记录工具目录',
          zhHant: '本次請求未記錄工具目錄',
          en: 'No tool catalog in this request',
          fr: 'Aucun catalogue d’outils enregistré pour cette requête',
          de: 'Für diese Anfrage wurde kein Werkzeugkatalog aufgezeichnet',
          ja: 'このリクエストにはツール一覧が記録されていません',
        ),
      ),
      'rendered' => _TrajectoryMarkdownDetail(
        text: _trajectoryRecordRawText(record),
        emptyText: _trajectoryText(
          context,
          zh: '无内容',
          zhHant: '無內容',
          en: 'No content',
          fr: 'Aucun contenu',
          de: 'Kein Inhalt',
          ja: '内容なし',
        ),
      ),
      'raw' => _TrajectoryStructuredDetail(
        text: _trajectoryRecordRawText(record),
        emptyText: _trajectoryText(
          context,
          zh: '无内容',
          zhHant: '無內容',
          en: 'No content',
          fr: 'Aucun contenu',
          de: 'Kein Inhalt',
          ja: '内容なし',
        ),
      ),
      'source' => _TrajectoryStructuredDetail(
        text: _trajectoryPrettyValue(<String, Object?>{
          'message_id': record.sourceMessageId,
          'turn': record.turn,
          'step': record.step,
          'request_number': record.requestNumber,
          'metadata': metadata,
        }),
        emptyText: _trajectoryText(
          context,
          zh: '未记录来源',
          zhHant: '未記錄來源',
          en: 'Source not recorded',
          fr: 'Source non enregistrée',
          de: 'Quelle nicht aufgezeichnet',
          ja: 'ソースは記録されていません',
        ),
      ),
      'input' => _TrajectoryStructuredDetail(
        text: record.input,
        emptyText: _trajectoryText(
          context,
          zh: '无输入载荷',
          zhHant: '無輸入載荷',
          en: 'No input payload',
          fr: 'Aucune charge utile d’entrée',
          de: 'Keine Eingabenutzlast',
          ja: '入力ペイロードなし',
        ),
      ),
      'output' => _TrajectoryStructuredDetail(
        text: record.output,
        emptyText: record.running
            ? _trajectoryText(
                context,
                zh: '等待中',
                zhHant: '等待中',
                en: 'Pending',
                fr: 'En attente',
                de: 'Ausstehend',
                ja: '待機中',
              )
            : _trajectoryText(
                context,
                zh: '无输出载荷',
                zhHant: '無輸出載荷',
                en: 'No output payload',
                fr: 'Aucune charge utile de sortie',
                de: 'Keine Ausgabenutzlast',
                ja: '出力ペイロードなし',
              ),
        error: record.isError,
      ),
      'schema' => _TrajectoryStructuredDetail(
        text: _trajectorySchema(metadata),
        emptyText: _trajectoryText(
          context,
          zh: '未记录结构',
          zhHant: '未記錄結構',
          en: 'Schema not recorded',
          fr: 'Schéma non enregistré',
          de: 'Schema nicht aufgezeichnet',
          ja: 'スキーマは記録されていません',
        ),
      ),
      'options' => _TrajectoryStructuredDetail(
        text: _trajectoryRequestOptions(metadata),
        emptyText: _trajectoryText(
          context,
          zh: '未记录请求选项',
          zhHant: '未記錄請求選項',
          en: 'Options not recorded',
          fr: 'Options de requête non enregistrées',
          de: 'Anfrageoptionen nicht aufgezeichnet',
          ja: 'リクエスト設定は記録されていません',
        ),
      ),
      'usage' => _buildUsage(context),
      'timing' => _buildTiming(context),
      _ => const SizedBox.shrink(),
    };
    return OpenHandSafeScrollbar(
      controller: scrollController,
      child: SingleChildScrollView(
        controller: scrollController,
        primary: false,
        physics: openHandDialogAwareScrollPhysics(context),
        padding: const EdgeInsets.all(14),
        child: OpenHandCrossFadeSwitcher(
          child: KeyedSubtree(key: ValueKey<String>(activeTab), child: content),
        ),
      ),
    );
  }

  Widget _buildSummary(BuildContext context) {
    final status = record.isError
        ? _trajectoryText(
            context,
            zh: '失败',
            zhHant: '失敗',
            en: 'Failed',
            fr: 'Échec',
            de: 'Fehlgeschlagen',
            ja: '失敗',
          )
        : record.running
        ? _trajectoryText(
            context,
            zh: '等待中',
            zhHant: '等待中',
            en: 'Pending',
            fr: 'En attente',
            de: 'Ausstehend',
            ja: '待機中',
          )
        : _trajectoryText(
            context,
            zh: '已完成',
            zhHant: '已完成',
            en: 'Completed',
            fr: 'Terminé',
            de: 'Abgeschlossen',
            ja: '完了',
          );
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
            (
              _trajectoryText(
                context,
                zh: '状态',
                zhHant: '狀態',
                en: 'Status',
                fr: 'État',
                de: 'Status',
                ja: '状態',
              ),
              status,
              record.isError,
            ),
            if (model != null)
              (
                _trajectoryText(
                  context,
                  zh: '模型',
                  zhHant: '模型',
                  en: 'Model',
                  fr: 'Modèle',
                  de: 'Modell',
                  ja: 'モデル',
                ),
                '$model',
                false,
              ),
            if (record.toolName != null)
              (
                _trajectoryText(
                  context,
                  zh: '工具',
                  zhHant: '工具',
                  en: 'Tool',
                  fr: 'Outil',
                  de: 'Werkzeug',
                  ja: 'ツール',
                ),
                record.toolName!,
                false,
              ),
            if (record.callId != null)
              (
                _trajectoryText(
                  context,
                  zh: '调用 ID',
                  zhHant: '呼叫 ID',
                  en: 'Call ID',
                  fr: 'ID d’appel',
                  de: 'Aufruf-ID',
                  ja: '呼び出し ID',
                ),
                record.callId!,
                false,
              ),
            if (record.kind == _TrajectoryKind.assistant)
              (
                _trajectoryText(
                  context,
                  zh: '令牌',
                  zhHant: 'Token',
                  en: 'Tokens',
                  fr: 'Tokens',
                  de: 'Token',
                  ja: 'トークン',
                ),
                record.usage?.completionTokens == null
                    ? '—'
                    : '${record.usage!.completionTokens} tok',
                false,
              ),
            (
              _trajectoryText(
                context,
                zh: '时长',
                zhHant: '時長',
                en: 'Duration',
                fr: 'Durée',
                de: 'Dauer',
                ja: '所要時間',
              ),
              _trajectoryDurationLabel(record.durationMs),
              false,
            ),
          ],
        ),
        if (_trajectoryRecordRawText(record).isNotEmpty) ...[
          kOpenHandGap16,
          _TrajectoryOverviewSection(
            title: record.kind == _TrajectoryKind.tool
                ? _trajectoryText(
                    context,
                    zh: '结果',
                    zhHant: '結果',
                    en: 'Result',
                    fr: 'Résultat',
                    de: 'Ergebnis',
                    ja: '結果',
                  )
                : _trajectoryText(
                    context,
                    zh: '预览',
                    zhHant: '預覽',
                    en: 'Preview',
                    fr: 'Aperçu',
                    de: 'Vorschau',
                    ja: 'プレビュー',
                  ),
            child: _TrajectoryMarkdownDetail(
              text: _trajectoryRecordRawText(record),
              emptyText: _trajectoryText(
                context,
                zh: '无内容',
                zhHant: '無內容',
                en: 'No content',
                fr: 'Aucun contenu',
                de: 'Kein Inhalt',
                ja: '内容なし',
              ),
              preview: true,
            ),
          ),
        ],
        if (record.kind == _TrajectoryKind.assistant) ...[
          kOpenHandGap16,
          _TrajectoryOverviewSection(
            title: _trajectoryText(
              context,
              zh: '用量',
              zhHant: '用量',
              en: 'Usage',
              fr: 'Utilisation',
              de: 'Verbrauch',
              ja: '使用量',
            ),
            child: _buildUsage(context, compact: true),
          ),
          kOpenHandGap16,
          _TrajectoryOverviewSection(
            title: _trajectoryText(
              context,
              zh: '耗时',
              zhHant: '耗時',
              en: 'Timing',
              fr: 'Temps',
              de: 'Zeit',
              ja: '時間',
            ),
            child: _buildTiming(context, compact: true),
          ),
        ],
      ],
    );
  }

  Widget _buildUsage(BuildContext context, {bool compact = false}) {
    final usage = record.usage;
    if (usage == null || usage.isEmpty) {
      return _TrajectoryEmptyDetail(
        text: _trajectoryText(
          context,
          zh: '未报告用量',
          zhHant: '未報告用量',
          en: 'Usage not reported',
          fr: 'Utilisation non rapportée',
          de: 'Verbrauch nicht gemeldet',
          ja: '使用量は報告されていません',
        ),
      );
    }
    final contentTokens =
        usage.completionTokens != null && usage.reasoningTokens != null
        ? math.max(0, usage.completionTokens! - usage.reasoningTokens!)
        : null;
    return _TrajectoryOverview(
      compact: compact,
      rows: <(String, String, bool)>[
        if (usage.promptTokens != null)
          (
            _trajectoryText(
              context,
              zh: '输入',
              zhHant: '輸入',
              en: 'Input',
              fr: 'Entrée',
              de: 'Eingabe',
              ja: '入力',
            ),
            '${usage.promptTokens} tok',
            false,
          ),
        if (usage.cacheReadTokens != null)
          (
            _trajectoryText(
              context,
              zh: '缓存读取',
              zhHant: '快取讀取',
              en: 'Cached',
              fr: 'Cache lu',
              de: 'Cache gelesen',
              ja: 'キャッシュ読込',
            ),
            '${usage.cacheReadTokens} tok',
            false,
          ),
        if (usage.cacheCreationTokens != null)
          (
            _trajectoryText(
              context,
              zh: '缓存创建',
              zhHant: '快取建立',
              en: 'Cache created',
              fr: 'Cache créé',
              de: 'Cache erstellt',
              ja: 'キャッシュ作成',
            ),
            '${usage.cacheCreationTokens} tok',
            false,
          ),
        if (usage.completionTokens != null)
          (
            _trajectoryText(
              context,
              zh: '输出',
              zhHant: '輸出',
              en: 'Output',
              fr: 'Sortie',
              de: 'Ausgabe',
              ja: '出力',
            ),
            '${usage.completionTokens} tok',
            false,
          ),
        if (usage.reasoningTokens != null)
          (
            _trajectoryText(
              context,
              zh: '推理',
              zhHant: '推理',
              en: 'Reasoning',
              fr: 'Raisonnement',
              de: 'Schlussfolgerung',
              ja: '推論',
            ),
            '${usage.reasoningTokens} tok',
            false,
          ),
        if (contentTokens != null)
          (
            _trajectoryText(
              context,
              zh: '正文',
              zhHant: '正文',
              en: 'Content',
              fr: 'Contenu',
              de: 'Inhalt',
              ja: '本文',
            ),
            '$contentTokens tok',
            false,
          ),
        if (usage.resolvedTotalTokens != null)
          (
            _trajectoryText(
              context,
              zh: '总计',
              zhHant: '總計',
              en: 'Total',
              fr: 'Total',
              de: 'Gesamt',
              ja: '合計',
            ),
            '${usage.resolvedTotalTokens} tok',
            false,
          ),
      ],
    );
  }

  Widget _buildTiming(BuildContext context, {bool compact = false}) {
    final firstToken = _trajectoryMetadataDate(metadata, const <String>[
      aiSessionMessageFirstTokenAtMetadataKey,
      'first_token_time',
      'first_visible_at',
    ]);
    final startedAt =
        _trajectoryMetadataDate(metadata, const <String>[
          aiSessionMessageRequestStartedAtMetadataKey,
          'started_at',
        ]) ??
        record.startedAt;
    final totalDuration =
        _trajectoryMetadataInt(metadata, const <String>[
          aiSessionMessageTotalDurationMsMetadataKey,
          'duration_ms',
        ]) ??
        record.durationMs;
    final ttft =
        _trajectoryMetadataInt(metadata, const <String>[
          aiSessionMessageTtftMsMetadataKey,
        ]) ??
        (startedAt != null && firstToken != null
            ? math.max(0, firstToken.difference(startedAt).inMilliseconds)
            : null);
    final generation =
        _trajectoryMetadataInt(metadata, const <String>[
          aiSessionMessageGenerationDurationMsMetadataKey,
        ]) ??
        (totalDuration != null && ttft != null
            ? math.max(0, totalDuration - ttft)
            : null);
    final outputTokens =
        record.usage?.completionTokens ??
        _trajectoryMetadataInt(metadata, const <String>['completion_tokens']);
    final outputCharacters = _trajectoryMetadataInt(metadata, const <String>[
      aiSessionMessageOutputCharactersMetadataKey,
    ]);
    final streamEvents = _trajectoryMetadataInt(metadata, const <String>[
      aiSessionMessageStreamEventCountMetadataKey,
    ]);
    final fallbackCount = _trajectoryMetadataInt(metadata, const <String>[
      'request_fallback_count',
    ]);
    final notRecorded = _trajectoryText(
      context,
      zh: '未记录',
      zhHant: '未記錄',
      en: 'Not recorded',
      fr: 'Non enregistré',
      de: 'Nicht aufgezeichnet',
      ja: '記録なし',
    );
    final tokensPerSecond =
        _trajectoryMetadataDouble(metadata, const <String>[
          aiSessionMessageTokensPerSecondMetadataKey,
        ]) ??
        (outputTokens != null && generation != null && generation > 0
            ? outputTokens / generation * 1000
            : null);
    final charactersPerSecond = _trajectoryMetadataDouble(
      metadata,
      const <String>[aiSessionMessageCharactersPerSecondMetadataKey],
    );
    final responseStatus = '${metadata['response_status'] ?? ''}'.trim();
    final statusLabel = switch (responseStatus) {
      'completed' => _trajectoryText(
        context,
        zh: '已完成',
        zhHant: '已完成',
        en: 'Completed',
        fr: 'Terminé',
        de: 'Abgeschlossen',
        ja: '完了',
      ),
      'cancelled' => _trajectoryText(
        context,
        zh: '已取消',
        zhHant: '已取消',
        en: 'Cancelled',
        fr: 'Annulé',
        de: 'Abgebrochen',
        ja: 'キャンセル済み',
      ),
      'failed' => _trajectoryText(
        context,
        zh: '失败',
        zhHant: '失敗',
        en: 'Failed',
        fr: 'Échec',
        de: 'Fehlgeschlagen',
        ja: '失敗',
      ),
      _ => '',
    };
    final overview = _TrajectoryOverview(
      compact: compact,
      rows: <(String, String, bool)>[
        (
          _trajectoryText(
            context,
            zh: '开始时间',
            zhHant: '開始時間',
            en: 'Started',
            fr: 'Début',
            de: 'Beginn',
            ja: '開始時刻',
          ),
          _trajectoryDateTimeLabel(startedAt),
          false,
        ),
        (
          _trajectoryText(
            context,
            zh: '总耗时',
            zhHant: '總耗時',
            en: 'Total duration',
            fr: 'Durée totale',
            de: 'Gesamtdauer',
            ja: '合計時間',
          ),
          _trajectoryDurationLabel(totalDuration),
          false,
        ),
        if (!compact)
          (
            _trajectoryText(
              context,
              zh: '首个响应',
              zhHant: '首個回應',
              en: 'First response',
              fr: 'Première réponse',
              de: 'Erste Antwort',
              ja: '最初の応答',
            ),
            firstToken == null
                ? notRecorded
                : _trajectoryDateTimeLabel(firstToken),
            false,
          ),
        (
          'TTFT',
          ttft == null ? notRecorded : _trajectoryDurationLabel(ttft),
          false,
        ),
        (
          _trajectoryText(
            context,
            zh: '生成耗时',
            zhHant: '生成耗時',
            en: 'Generation',
            fr: 'Génération',
            de: 'Generierung',
            ja: '生成時間',
          ),
          generation == null
              ? notRecorded
              : _trajectoryDurationLabel(generation),
          false,
        ),
        (
          _trajectoryText(
            context,
            zh: '吞吐率',
            zhHant: '吞吐率',
            en: 'Throughput',
            fr: 'Débit',
            de: 'Durchsatz',
            ja: 'スループット',
          ),
          tokensPerSecond == null
              ? notRecorded
              : '${tokensPerSecond.toStringAsFixed(1)} tok/s',
          false,
        ),
        if (!compact && charactersPerSecond != null)
          (
            _trajectoryText(
              context,
              zh: '字符吞吐率',
              zhHant: '字元吞吐率',
              en: 'Character throughput',
              fr: 'Débit de caractères',
              de: 'Zeichendurchsatz',
              ja: '文字スループット',
            ),
            '${charactersPerSecond.toStringAsFixed(1)} char/s',
            false,
          ),
        if (!compact && outputCharacters != null)
          (
            _trajectoryText(
              context,
              zh: '输出字符',
              zhHant: '輸出字元',
              en: 'Output characters',
              fr: 'Caractères produits',
              de: 'Ausgabezeichen',
              ja: '出力文字数',
            ),
            '$outputCharacters',
            false,
          ),
        if (!compact && streamEvents != null)
          (
            _trajectoryText(
              context,
              zh: '流事件',
              zhHant: '串流事件',
              en: 'Stream events',
              fr: 'Événements du flux',
              de: 'Stream-Ereignisse',
              ja: 'ストリームイベント',
            ),
            '$streamEvents',
            false,
          ),
        if (!compact && fallbackCount != null)
          (
            _trajectoryText(
              context,
              zh: '请求降级',
              zhHant: '請求降級',
              en: 'Request fallbacks',
              fr: 'Replis de requête',
              de: 'Anfrage-Fallbacks',
              ja: 'リクエストフォールバック',
            ),
            '$fallbackCount',
            false,
          ),
        if (!compact && '${metadata['finish_reason'] ?? ''}'.trim().isNotEmpty)
          (
            _trajectoryText(
              context,
              zh: '结束原因',
              zhHant: '結束原因',
              en: 'Finish reason',
              fr: 'Motif de fin',
              de: 'Endgrund',
              ja: '終了理由',
            ),
            '${metadata['finish_reason']}',
            false,
          ),
        if (!compact && statusLabel.isNotEmpty)
          (
            _trajectoryText(
              context,
              zh: '响应状态',
              zhHant: '回應狀態',
              en: 'Response status',
              fr: 'État de la réponse',
              de: 'Antwortstatus',
              ja: '応答状態',
            ),
            statusLabel,
            responseStatus == 'failed',
          ),
      ],
    );
    final samples = _trajectoryMetadataNumberList(
      metadata,
      aiSessionMessageStreamThroughputSamplesMetadataKey,
    );
    if (compact || samples.isEmpty) return overview;
    final intervalMs =
        _trajectoryMetadataInt(metadata, const <String>[
          aiSessionMessageStreamThroughputIntervalMetadataKey,
        ]) ??
        1000;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        overview,
        kOpenHandGap12,
        _TrajectoryThroughputChart(
          samples: samples,
          sampleIntervalMs: intervalMs,
          outputCharacters: outputCharacters,
          outputTokens: outputTokens,
        ),
      ],
    );
  }
}

class _TrajectoryThroughputChart extends StatelessWidget {
  const _TrajectoryThroughputChart({
    required this.samples,
    required this.sampleIntervalMs,
    required this.outputCharacters,
    required this.outputTokens,
  });

  final List<double> samples;
  final int sampleIntervalMs;
  final int? outputCharacters;
  final int? outputTokens;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tokenRatio =
        outputCharacters != null &&
            outputCharacters! > 0 &&
            outputTokens != null
        ? outputTokens! / outputCharacters!
        : null;
    final tokenSamples = tokenRatio == null
        ? const <double>[]
        : samples.map((value) => value * tokenRatio).toList(growable: false);
    final peakCharacters = samples.reduce(math.max);
    final peakTokens = tokenSamples.isEmpty
        ? null
        : tokenSamples.reduce(math.max);
    final intervalSeconds = sampleIntervalMs / 1000;
    final intervalLabel = intervalSeconds == intervalSeconds.roundToDouble()
        ? '${intervalSeconds.toInt()}'
        : intervalSeconds.toStringAsFixed(1);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.72),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _trajectoryText(
              context,
              zh: '响应吞吐趋势',
              zhHant: '回應吞吐趨勢',
              en: 'Response throughput trend',
              fr: 'Tendance du débit de réponse',
              de: 'Trend des Antwortdurchsatzes',
              ja: '応答スループット推移',
            ),
            style: theme.textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          kOpenHandGap4,
          Text(
            _trajectoryText(
              context,
              zh: '每 $intervalLabel 秒采样 · ${samples.length} 个点',
              zhHant: '每 $intervalLabel 秒取樣 · ${samples.length} 個點',
              en: '$intervalLabel s sampling · ${samples.length} points',
              fr: 'Échantillon toutes les $intervalLabel s · ${samples.length} points',
              de: 'Abtastung alle $intervalLabel s · ${samples.length} Punkte',
              ja: '$intervalLabel 秒ごと · ${samples.length} 点',
            ),
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          kOpenHandGap8,
          Wrap(
            spacing: 12,
            runSpacing: 5,
            children: [
              _TrajectoryThroughputLegend(
                color: colorScheme.primary,
                label: _trajectoryText(
                  context,
                  zh: '字符/秒 · 峰值 ${peakCharacters.toStringAsFixed(1)}',
                  zhHant: '字元/秒 · 峰值 ${peakCharacters.toStringAsFixed(1)}',
                  en: 'Characters/s · peak ${peakCharacters.toStringAsFixed(1)}',
                  fr: 'Caractères/s · pic ${peakCharacters.toStringAsFixed(1)}',
                  de: 'Zeichen/s · Spitze ${peakCharacters.toStringAsFixed(1)}',
                  ja: '文字/秒 · 最大 ${peakCharacters.toStringAsFixed(1)}',
                ),
              ),
              if (peakTokens != null)
                _TrajectoryThroughputLegend(
                  color: colorScheme.tertiary,
                  label: _trajectoryText(
                    context,
                    zh: '估算 Token/秒 · 峰值 ${peakTokens.toStringAsFixed(1)}',
                    zhHant: '估算 Token/秒 · 峰值 ${peakTokens.toStringAsFixed(1)}',
                    en: 'Estimated tokens/s · peak ${peakTokens.toStringAsFixed(1)}',
                    fr: 'Tokens/s estimés · pic ${peakTokens.toStringAsFixed(1)}',
                    de: 'Geschätzte Token/s · Spitze ${peakTokens.toStringAsFixed(1)}',
                    ja: '推定 Token/秒 · 最大 ${peakTokens.toStringAsFixed(1)}',
                  ),
                ),
            ],
          ),
          kOpenHandGap8,
          SizedBox(
            height: 132,
            child: CustomPaint(
              painter: _TrajectoryThroughputPainter(
                characterSamples: samples,
                tokenSamples: tokenSamples,
                characterColor: colorScheme.primary,
                tokenColor: colorScheme.tertiary,
                gridColor: colorScheme.outlineVariant.withValues(alpha: 0.58),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrajectoryThroughputLegend extends StatelessWidget {
  const _TrajectoryThroughputLegend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        kOpenHandHGap4,
        Flexible(
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
      ],
    );
  }
}

class _TrajectoryThroughputPainter extends CustomPainter {
  const _TrajectoryThroughputPainter({
    required this.characterSamples,
    required this.tokenSamples,
    required this.characterColor,
    required this.tokenColor,
    required this.gridColor,
  });

  final List<double> characterSamples;
  final List<double> tokenSamples;
  final Color characterColor;
  final Color tokenColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (characterSamples.isEmpty || size.isEmpty) return;
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var row = 0; row <= 3; row++) {
      final y = size.height * row / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    final characterPoints = _points(characterSamples, size);
    final characterPath = _smoothPath(characterPoints);
    if (characterPoints.length > 1) {
      final areaPath = Path.from(characterPath)
        ..lineTo(characterPoints.last.dx, size.height)
        ..lineTo(characterPoints.first.dx, size.height)
        ..close();
      canvas.drawPath(
        areaPath,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              characterColor.withValues(alpha: 0.3),
              characterColor.withValues(alpha: 0.02),
            ],
          ).createShader(Offset.zero & size),
      );
    }
    _drawSeries(canvas, characterPoints, characterPath, characterColor, 2.2);
    if (tokenSamples.isNotEmpty) {
      final tokenPoints = _points(tokenSamples, size);
      _drawSeries(
        canvas,
        tokenPoints,
        _smoothPath(tokenPoints),
        tokenColor,
        1.35,
      );
    }
  }

  List<Offset> _points(List<double> values, Size size) {
    final peak = values.fold<double>(0, math.max);
    final scale = peak <= 0 ? 1.0 : peak;
    return List<Offset>.generate(values.length, (index) {
      final x = values.length == 1
          ? size.width / 2
          : size.width * index / (values.length - 1);
      final normalized = (values[index] / scale).clamp(0.0, 1.0);
      return Offset(x, size.height - normalized * (size.height - 6) - 3);
    }, growable: false);
  }

  Path _smoothPath(List<Offset> points) {
    final path = Path();
    if (points.isEmpty) return path;
    path.moveTo(points.first.dx, points.first.dy);
    for (var index = 0; index < points.length - 1; index++) {
      final previous = index == 0 ? points[index] : points[index - 1];
      final current = points[index];
      final next = points[index + 1];
      final following = index + 2 < points.length ? points[index + 2] : next;
      path.cubicTo(
        current.dx + (next.dx - previous.dx) / 6,
        current.dy + (next.dy - previous.dy) / 6,
        next.dx - (following.dx - current.dx) / 6,
        next.dy - (following.dy - current.dy) / 6,
        next.dx,
        next.dy,
      );
    }
    return path;
  }

  void _drawSeries(
    Canvas canvas,
    List<Offset> points,
    Path path,
    Color color,
    double strokeWidth,
  ) {
    if (points.length == 1) {
      canvas.drawCircle(points.first, 3, Paint()..color = color);
      return;
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _TrajectoryThroughputPainter oldDelegate) {
    return !listEquals(characterSamples, oldDelegate.characterSamples) ||
        !listEquals(tokenSamples, oldDelegate.tokenSamples) ||
        characterColor != oldDelegate.characterColor ||
        tokenColor != oldDelegate.tokenColor ||
        gridColor != oldDelegate.gridColor;
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
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 8.0;
        final columns = constraints.maxWidth >= 360 ? 2 : 1;
        final width = columns == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - gap) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final row in rows)
              SizedBox(
                width: width,
                child: Container(
                  constraints: BoxConstraints(minHeight: compact ? 54 : 62),
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 9 : 10,
                    vertical: compact ? 7 : 9,
                  ),
                  decoration: BoxDecoration(
                    color: row.$3
                        ? colorScheme.errorContainer.withValues(alpha: 0.5)
                        : colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(
                      color: row.$3
                          ? colorScheme.error.withValues(alpha: 0.32)
                          : colorScheme.outlineVariant.withValues(alpha: 0.72),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        row.$1,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: row.$3
                              ? colorScheme.error
                              : colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      kOpenHandGap4,
                      SelectableText(
                        row.$2,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: row.$3 ? colorScheme.error : null,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
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

class _TrajectoryMarkdownDetail extends StatefulWidget {
  const _TrajectoryMarkdownDetail({
    required this.text,
    required this.emptyText,
    this.preview = false,
  });

  final String text;
  final String emptyText;
  final bool preview;

  @override
  State<_TrajectoryMarkdownDetail> createState() =>
      _TrajectoryMarkdownDetailState();
}

class _TrajectoryMarkdownDetailState extends State<_TrajectoryMarkdownDetail> {
  final ScrollController _previewScrollController = ScrollController();

  @override
  void dispose() {
    _previewScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    if (widget.text.trim().isEmpty) {
      return _TrajectoryEmptyDetail(text: widget.emptyText);
    }
    final content = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: OpenHandSafeMarkdownBody(
        data: widget.text,
        selectable: true,
        styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
          p: theme.textTheme.bodySmall?.copyWith(height: 1.5),
          code: theme.textTheme.bodySmall?.copyWith(
            fontFamily: kOpenHandMonospaceFontFamily,
          ),
        ),
      ),
    );
    if (!widget.preview) return content;
    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxHeight: _kTrajectoryPreviewMaxHeight,
      ),
      child: OpenHandSafeScrollbar(
        controller: _previewScrollController,
        child: SingleChildScrollView(
          controller: _previewScrollController,
          primary: false,
          physics: openHandDialogAwareScrollPhysics(context),
          child: content,
        ),
      ),
    );
  }
}

class _TrajectoryJsonDocument {
  const _TrajectoryJsonDocument({
    required this.value,
    required this.containerPaths,
  });

  final Object? value;
  final Set<String> containerPaths;
}

_TrajectoryJsonDocument? _trajectoryJsonDocument(String text) {
  final trimmed = text.trim();
  if (trimmed.length < 2 ||
      trimmed.length > _kTrajectoryJsonTreeMaxCharacters ||
      !(trimmed.startsWith('{') && trimmed.endsWith('}')) &&
          !(trimmed.startsWith('[') && trimmed.endsWith(']'))) {
    return null;
  }
  Object? decoded;
  try {
    decoded = jsonDecode(trimmed);
  } on FormatException {
    return null;
  }
  if (decoded is! Map && decoded is! List) return null;

  final paths = <String>{r'$'};
  final pending = <(Object?, String, int)>[(decoded, r'$', 0)];
  var nodes = 0;
  while (pending.isNotEmpty) {
    final current = pending.removeLast();
    if (current.$3 > _kTrajectoryJsonTreeMaxDepth) return null;
    final value = current.$1;
    final children = value is Map
        ? value.values.toList(growable: false)
        : value is List
        ? value
        : const <Object?>[];
    for (var index = 0; index < children.length; index += 1) {
      nodes += 1;
      if (nodes > _kTrajectoryJsonTreeMaxNodes) return null;
      final child = children[index];
      if ((child is Map && child.isNotEmpty) ||
          (child is List && child.isNotEmpty)) {
        final path = '${current.$2}/$index';
        paths.add(path);
        pending.add((child, path, current.$3 + 1));
      }
    }
  }
  return _TrajectoryJsonDocument(
    value: decoded,
    containerPaths: Set<String>.unmodifiable(paths),
  );
}

class _TrajectoryStructuredDetail extends StatefulWidget {
  const _TrajectoryStructuredDetail({
    required this.text,
    required this.emptyText,
    this.error = false,
  });

  final String text;
  final String emptyText;
  final bool error;

  @override
  State<_TrajectoryStructuredDetail> createState() =>
      _TrajectoryStructuredDetailState();
}

class _TrajectoryStructuredDetailState
    extends State<_TrajectoryStructuredDetail> {
  _TrajectoryJsonDocument? _document;
  Set<String> _expandedPaths = <String>{r'$'};
  Timer? _copiedResetTimer;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void didUpdateWidget(covariant _TrajectoryStructuredDetail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _copiedResetTimer?.cancel();
      _copied = false;
      _parse();
    }
  }

  @override
  void dispose() {
    _copiedResetTimer?.cancel();
    super.dispose();
  }

  void _parse() {
    _document = _trajectoryJsonDocument(widget.text);
    _expandedPaths = <String>{
      r'$',
      ...?_document?.containerPaths.where(
        (path) => path != r'$' && '/'.allMatches(path).length == 1,
      ),
    };
  }

  Future<void> _copy() async {
    final copied = await copyOpenHandTextToClipboard(
      context: context,
      text: widget.text,
      logTag: 'trajectory',
      logAction: '复制轨迹详情',
      showSuccess: false,
    );
    if (!copied || !mounted) return;
    _copiedResetTimer?.cancel();
    setState(() => _copied = true);
    _copiedResetTimer = startSafeTimer(_kTrajectoryCopyFeedbackDuration, () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.text.trim().isEmpty) {
      return _TrajectoryEmptyDetail(text: widget.emptyText);
    }
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final document = _document;
    final value = document?.value;
    final count = value is Map
        ? value.length
        : value is List
        ? value.length
        : 0;
    final description = value is Map
        ? _trajectoryText(
            context,
            zh: '对象 · $count 个字段',
            zhHant: '物件 · $count 個欄位',
            en: 'Object · $count ${count == 1 ? 'field' : 'fields'}',
            fr: 'Objet · $count ${count == 1 ? 'champ' : 'champs'}',
            de: 'Objekt · $count ${count == 1 ? 'Feld' : 'Felder'}',
            ja: 'オブジェクト · $count フィールド',
          )
        : value is List
        ? _trajectoryText(
            context,
            zh: '数组 · $count 项',
            zhHant: '陣列 · $count 項',
            en: 'Array · $count ${count == 1 ? 'item' : 'items'}',
            fr: 'Tableau · $count ${count == 1 ? 'élément' : 'éléments'}',
            de: 'Array · $count ${count == 1 ? 'Eintrag' : 'Einträge'}',
            ja: '配列 · $count 件',
          )
        : _trajectoryText(
            context,
            zh: '文本 · ${widget.text.length} 字符',
            zhHant: '文字 · ${widget.text.length} 字元',
            en: 'Text · ${widget.text.length} characters',
            fr: 'Texte · ${widget.text.length} caractères',
            de: 'Text · ${widget.text.length} Zeichen',
            ja: 'テキスト · ${widget.text.length} 文字',
          );
    final allExpanded =
        document != null &&
        document.containerPaths.every(_expandedPaths.contains);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: widget.error
              ? colorScheme.error.withValues(alpha: 0.38)
              : colorScheme.outlineVariant.withValues(alpha: 0.78),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 38,
            padding: const EdgeInsetsDirectional.only(start: 10, end: 4),
            decoration: BoxDecoration(
              color: widget.error
                  ? colorScheme.errorContainer.withValues(alpha: 0.5)
                  : document == null
                  ? colorScheme.surfaceContainerHigh.withValues(alpha: 0.72)
                  : colorScheme.primaryContainer.withValues(alpha: 0.38),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(6),
              ),
              border: Border(
                bottom: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.72),
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  document == null
                      ? Icons.notes_rounded
                      : Icons.data_object_rounded,
                  size: 16,
                  color: widget.error
                      ? colorScheme.error
                      : document == null
                      ? colorScheme.onSurfaceVariant
                      : colorScheme.primary,
                ),
                kOpenHandHGap8,
                Expanded(
                  child: Text(
                    description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (document != null && document.containerPaths.length > 1) ...[
                  IconButton(
                    constraints: const BoxConstraints.tightFor(
                      width: 30,
                      height: 30,
                    ),
                    padding: EdgeInsets.zero,
                    tooltip: allExpanded
                        ? _trajectoryText(
                            context,
                            zh: '全部收起',
                            zhHant: '全部收合',
                            en: 'Collapse all',
                            fr: 'Tout réduire',
                            de: 'Alle einklappen',
                            ja: 'すべて折りたたむ',
                          )
                        : _trajectoryText(
                            context,
                            zh: '全部展开',
                            zhHant: '全部展開',
                            en: 'Expand all',
                            fr: 'Tout développer',
                            de: 'Alle ausklappen',
                            ja: 'すべて展開',
                          ),
                    onPressed: () => setState(() {
                      _expandedPaths = allExpanded
                          ? <String>{r'$'}
                          : document.containerPaths.toSet();
                    }),
                    icon: Icon(
                      allExpanded
                          ? Icons.unfold_less_rounded
                          : Icons.unfold_more_rounded,
                      size: 17,
                    ),
                  ),
                  kOpenHandHGap4,
                ],
                IconButton(
                  constraints: const BoxConstraints.tightFor(
                    width: 30,
                    height: 30,
                  ),
                  padding: EdgeInsets.zero,
                  tooltip: _copied
                      ? _trajectoryText(
                          context,
                          zh: '已复制',
                          zhHant: '已複製',
                          en: 'Copied',
                          fr: 'Copié',
                          de: 'Kopiert',
                          ja: 'コピー済み',
                        )
                      : _trajectoryText(
                          context,
                          zh: document == null ? '复制文本' : '复制 JSON',
                          zhHant: document == null ? '複製文字' : '複製 JSON',
                          en: document == null ? 'Copy text' : 'Copy JSON',
                          fr: document == null
                              ? 'Copier le texte'
                              : 'Copier le JSON',
                          de: document == null
                              ? 'Text kopieren'
                              : 'JSON kopieren',
                          ja: document == null ? 'テキストをコピー' : 'JSON をコピー',
                        ),
                  onPressed: _copy,
                  icon: Icon(
                    _copied ? Icons.check_rounded : Icons.copy_rounded,
                    size: 16,
                    color: _copied ? colorScheme.primary : null,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: document == null
                ? SelectableText(
                    widget.text,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: kOpenHandMonospaceFontFamily,
                      color: widget.error ? colorScheme.error : null,
                      height: 1.5,
                    ),
                  )
                : _buildJsonRoot(context, document.value),
          ),
        ],
      ),
    );
  }

  Widget _buildJsonRoot(BuildContext context, Object? value) {
    final entries = value is Map
        ? value.entries
              .map((entry) => (key: '${entry.key}', value: entry.value))
              .toList(growable: false)
        : [
            for (var index = 0; index < (value as List).length; index += 1)
              (key: '$index', value: value[index]),
          ];
    if (entries.isEmpty) {
      final theme = Theme.of(context);
      return SelectableText(
        value is Map ? '{}' : '[]',
        style: theme.textTheme.bodySmall?.copyWith(
          fontFamily: kOpenHandMonospaceFontFamily,
          color: theme.colorScheme.onSurfaceVariant,
          height: 1.45,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < entries.length; index += 1)
          _buildJsonNode(
            context,
            key: entries[index].key,
            value: entries[index].value,
            path:
                r'$'
                '/$index',
            depth: 0,
          ),
      ],
    );
  }

  Widget _buildJsonNode(
    BuildContext context, {
    required String key,
    required Object? value,
    required String path,
    required int depth,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final jsonColors = theme.brightness == Brightness.dark
        ? _kTrajectoryJsonDarkColors
        : _kTrajectoryJsonLightColors;
    final isContainer = value is Map || value is List;
    final childCount = value is Map
        ? value.length
        : value is List
        ? value.length
        : 0;
    final expandable = isContainer && childCount > 0;
    final expanded = expandable && _expandedPaths.contains(path);
    final keyStyle = theme.textTheme.bodySmall?.copyWith(
      fontFamily: kOpenHandMonospaceFontFamily,
      color: jsonColors.key,
      fontWeight: FontWeight.w600,
      height: 1.45,
    );
    final punctuationStyle = keyStyle?.copyWith(
      color: jsonColors.punctuation,
      fontWeight: FontWeight.w400,
    );
    final valueSpan = TextSpan(
      style: keyStyle,
      children: [
        TextSpan(text: jsonEncode(key)),
        TextSpan(text: ': ', style: punctuationStyle),
        if (isContainer) ...[
          TextSpan(
            text: value is Map
                ? childCount == 0
                      ? '{}'
                      : '{…}'
                : childCount == 0
                ? '[]'
                : '[…]',
            style: punctuationStyle,
          ),
          if (childCount > 0)
            TextSpan(
              text: '  $childCount',
              style: punctuationStyle?.copyWith(color: jsonColors.count),
            ),
        ] else
          TextSpan(
            text: jsonEncode(value),
            style: _trajectoryJsonValueStyle(theme, value),
          ),
      ],
    );
    final row = Padding(
      padding: EdgeInsetsDirectional.only(start: depth == 0 ? 0 : 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 20,
            height: 22,
            child: expandable
                ? AnimatedRotation(
                    turns: expanded ? 0.25 : 0,
                    duration: cardMotionDurationFor(
                      context,
                      expanding: expanded,
                    ),
                    curve: kCardMotionCurve,
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 17,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  )
                : Icon(Icons.circle, size: 4, color: colorScheme.outline),
          ),
          Expanded(
            child: expandable
                ? Text.rich(valueSpan)
                : SelectableText.rich(valueSpan),
          ),
        ],
      ),
    );
    if (!expandable) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: row,
      );
    }

    final children = value is Map
        ? value.entries
              .map((entry) => (key: '${entry.key}', value: entry.value))
              .toList(growable: false)
        : [
            for (var index = 0; index < (value as List).length; index += 1)
              (key: '$index', value: value[index]),
          ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          borderRadius: kOpenHandBorderRadius4,
          onTap: () => setState(() {
            if (expanded) {
              _expandedPaths.remove(path);
            } else {
              _expandedPaths.add(path);
            }
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: row,
          ),
        ),
        maybeAnimatedSize(
          duration: cardMotionDurationFor(context, expanding: expanded),
          curve: kCardMotionCurve,
          alignment: Alignment.topCenter,
          child: expanded
              ? Container(
                  margin: const EdgeInsetsDirectional.only(start: 9),
                  padding: const EdgeInsetsDirectional.only(start: 4),
                  decoration: BoxDecoration(
                    border: BorderDirectional(
                      start: BorderSide(
                        color: jsonColors.key.withValues(alpha: 0.28),
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var index = 0; index < children.length; index += 1)
                        _buildJsonNode(
                          context,
                          key: children[index].key,
                          value: children[index].value,
                          path: '$path/$index',
                          depth: depth + 1,
                        ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

TextStyle? _trajectoryJsonValueStyle(ThemeData theme, Object? value) {
  final colors = theme.brightness == Brightness.dark
      ? _kTrajectoryJsonDarkColors
      : _kTrajectoryJsonLightColors;
  final color = switch (value) {
    String() => colors.string,
    num() => colors.number,
    bool() => colors.boolValue,
    null => colors.nullValue,
    _ => theme.colorScheme.onSurface,
  };
  return theme.textTheme.bodySmall?.copyWith(
    fontFamily: kOpenHandMonospaceFontFamily,
    color: color,
    fontWeight: value is bool ? FontWeight.w700 : FontWeight.w500,
    height: 1.45,
  );
}

class _TrajectoryEmptyDetail extends StatelessWidget {
  const _TrajectoryEmptyDetail({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.62),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 16,
            color: colorScheme.onSurfaceVariant,
          ),
          kOpenHandHGap8,
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
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
  if (value == null) {
    return openHandAmbientText(
      zh: '不可用',
      zhHant: '不可用',
      en: 'Not available',
      fr: 'Indisponible',
      de: 'Nicht verfügbar',
      ja: '利用不可',
    );
  }
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  String three(int number) => number.toString().padLeft(3, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}:${two(local.second)}.'
      '${three(local.millisecond)}';
}

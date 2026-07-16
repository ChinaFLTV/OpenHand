import '../../../shared/util/input_value_parsing.dart';

enum McpToolCatalogStatus { idle, loading, ready, failed }

class McpToolCatalog {
  const McpToolCatalog({
    this.status = McpToolCatalogStatus.idle,
    this.tools = const <McpTool>[],
    this.isComplete = true,
    this.errorMessage,
    this.warningMessage,
    this.serverInstructions = '',
    this.lastScannedAt,
  });

  final McpToolCatalogStatus status;
  final List<McpTool> tools;
  final bool isComplete;
  final String? errorMessage;
  final String? warningMessage;
  final String serverInstructions;
  final DateTime? lastScannedAt;

  bool get isLoading => status == McpToolCatalogStatus.loading;
  bool get hasError =>
      status == McpToolCatalogStatus.failed &&
      nullIfBlank(errorMessage) != null;
  bool get hasWarning => nullIfBlank(warningMessage) != null;

  McpToolCatalog copyWith({
    McpToolCatalogStatus? status,
    List<McpTool>? tools,
    bool? isComplete,
    String? errorMessage,
    bool clearErrorMessage = false,
    String? warningMessage,
    bool clearWarningMessage = false,
    String? serverInstructions,
    bool clearServerInstructions = false,
    DateTime? lastScannedAt,
  }) {
    return McpToolCatalog(
      status: status ?? this.status,
      tools: tools ?? this.tools,
      isComplete: isComplete ?? this.isComplete,
      errorMessage: clearErrorMessage
          ? null
          : errorMessage ?? this.errorMessage,
      warningMessage: clearWarningMessage
          ? null
          : warningMessage ?? this.warningMessage,
      serverInstructions: clearServerInstructions
          ? ''
          : serverInstructions ?? this.serverInstructions,
      lastScannedAt: lastScannedAt ?? this.lastScannedAt,
    );
  }
}

class McpTool {
  const McpTool({
    required this.id,
    required this.name,
    required this.description,
    required this.inputSchema,
    this.outputSchema,
    this.outputDescription,
    this.outputDescriptionIsInferred = false,
    this.annotations = const <String, Object?>{},
    this.execution = const <String, Object?>{},
    this.rawInputSchema,
    this.rawOutputSchema,
    this.rawMetadata = const <String, Object?>{},
    this.metadataWarning,
  });

  final String id;
  final String name;
  final String description;
  final Map<String, Object?> inputSchema;
  final Map<String, Object?>? outputSchema;
  final String? outputDescription;
  final bool outputDescriptionIsInferred;
  final Map<String, Object?> annotations;
  final Map<String, Object?> execution;
  final Object? rawInputSchema;
  final Object? rawOutputSchema;
  final Map<String, Object?> rawMetadata;
  final String? metadataWarning;

  bool get hasMetadataWarning => nullIfBlank(metadataWarning) != null;
  bool get hasOutputSchema =>
      rawOutputSchema != null ||
      (outputSchema != null && outputSchema!.isNotEmpty);
  bool get hasRawMetadata => rawMetadata.isNotEmpty;
}

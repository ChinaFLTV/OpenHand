import '../../../shared/util/bounded_json_conversion.dart';
import '../../../shared/util/input_value_parsing.dart';

const int kMcpMaxCatalogToolCount = 4096;
const int kMcpMaxCatalogScannedEntryCount = 8192;
const int kMcpMaxCatalogMetadataNodeCount = 262144;
const int kMcpMaxCatalogTextCodeUnits = 16 * 1024 * 1024;
const int kMcpMaxServerInstructionsCodeUnits = 256 * 1024;
const int kMcpMaxToolIdCodeUnits = 1024;
const int kMcpMaxToolMetadataDepth = 64;
const int kMcpMaxToolMetadataContainerItems = 8192;
const int kMcpMaxToolMetadataNodeCount = 32768;
const int kMcpMaxToolMetadataStringCodeUnits = 256 * 1024;
const int kMcpMaxToolMetadataTextCodeUnits = 1024 * 1024;

JsonValueMetrics? measureMcpToolMetadata(Object? value) {
  return measureJsonValueWithinBounds(
    value,
    maxDepth: kMcpMaxToolMetadataDepth,
    maxContainerItems: kMcpMaxToolMetadataContainerItems,
    maxTotalNodes: kMcpMaxToolMetadataNodeCount,
    maxStringCodeUnits: kMcpMaxToolMetadataStringCodeUnits,
    maxTotalStringCodeUnits: kMcpMaxToolMetadataTextCodeUnits,
  );
}

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

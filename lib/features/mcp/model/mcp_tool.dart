enum McpToolCatalogStatus { idle, loading, ready, failed }

class McpToolCatalog {
  const McpToolCatalog({
    this.status = McpToolCatalogStatus.idle,
    this.tools = const <McpTool>[],
    this.errorMessage,
    this.warningMessage,
    this.lastScannedAt,
  });

  final McpToolCatalogStatus status;
  final List<McpTool> tools;
  final String? errorMessage;
  final String? warningMessage;
  final DateTime? lastScannedAt;

  bool get isLoading => status == McpToolCatalogStatus.loading;
  bool get hasError =>
      status == McpToolCatalogStatus.failed &&
      (errorMessage?.trim().isNotEmpty ?? false);
  bool get hasWarning => warningMessage?.trim().isNotEmpty ?? false;

  McpToolCatalog copyWith({
    McpToolCatalogStatus? status,
    List<McpTool>? tools,
    String? errorMessage,
    bool clearErrorMessage = false,
    String? warningMessage,
    bool clearWarningMessage = false,
    DateTime? lastScannedAt,
  }) {
    return McpToolCatalog(
      status: status ?? this.status,
      tools: tools ?? this.tools,
      errorMessage: clearErrorMessage
          ? null
          : errorMessage ?? this.errorMessage,
      warningMessage: clearWarningMessage
          ? null
          : warningMessage ?? this.warningMessage,
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
  final Map<String, Object?> annotations;
  final Map<String, Object?> execution;
  final Object? rawInputSchema;
  final Object? rawOutputSchema;
  final Map<String, Object?> rawMetadata;
  final String? metadataWarning;

  bool get hasMetadataWarning => metadataWarning?.trim().isNotEmpty ?? false;
  bool get hasOutputSchema =>
      rawOutputSchema != null ||
      (outputSchema != null && outputSchema!.isNotEmpty);
  bool get hasRawMetadata => rawMetadata.isNotEmpty;
}

part of 'settings_view.dart';

class _AiModelEditorDialog extends StatefulWidget {
  const _AiModelEditorDialog({this.initialModel});

  final AiModelConfig? initialModel;

  @override
  State<_AiModelEditorDialog> createState() => _AiModelEditorDialogState();
}

class _AiModelEditorDialogState extends State<_AiModelEditorDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _baseUrlController;
  late final TextEditingController _tokenController;
  late final TextEditingController _modelIdController;
  late final TextEditingController _maxContextTokensController;
  late final TextEditingController _manualModelIdController;
  late final TextEditingController _maxTokensController;
  late final TextEditingController _temperatureController;
  late AiAuthScheme _authScheme;
  late AiProtocolType _protocolType;
  late AiApiDialect _apiDialect;
  late AiProviderKind _providerKind;
  late String _requestMethod;
  late bool _streamEnabled;
  late final TextEditingController _responsesModelIdController;
  late final TextEditingController _embeddingModelIdController;
  late final TextEditingController _moderationModelIdController;
  late final TextEditingController _rerankModelIdController;
  late final TextEditingController _imageModelIdController;
  late final TextEditingController _videoModelIdController;
  late final TextEditingController _speechModelIdController;
  late final TextEditingController _transcriptionModelIdController;
  late final TextEditingController _translationModelIdController;
  late final TextEditingController _realtimeModelIdController;
  late final TextEditingController _defaultVoiceController;
  late final TextEditingController _realtimeTransportController;
  late final TextEditingController _realtimeUrlOverrideController;
  late final TextEditingController _endpointOverridesController;
  late final TextEditingController _operationExtrasController;
  bool _obscureToken = true;
  bool _isSaving = false;
  bool _isScanning = false;
  String? _errorMessage;
  String? _scanError;
  final ValueNotifier<int> _errorPulse = ValueNotifier<int>(0);
  List<String> _availableModelIds = const <String>[];
  String? _activeModelId;
  late Map<String, AiModelProfile> _modelProfiles;
  late List<_HeaderEntry> _customHeaderEntries;
  final ScrollController _chipScrollController = ScrollController();

  List<String> get _visibleModelIds => AiModelConfig.normalizeModelIds(<String>[
    ..._availableModelIds,
    if ((_activeModelId ?? '').trim().isNotEmpty) _activeModelId!.trim(),
  ]);

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.initialModel?.name ?? '',
    );
    _baseUrlController = TextEditingController(
      text: widget.initialModel?.baseUrl ?? '',
    );
    _tokenController = TextEditingController(
      text: widget.initialModel?.token ?? '',
    );
    _modelIdController = TextEditingController(
      text: widget.initialModel?.modelId ?? '',
    );
    _maxContextTokensController = TextEditingController(
      text: widget.initialModel?.maxContextTokens?.toString() ?? '',
    );
    _manualModelIdController = TextEditingController();
    _maxTokensController = TextEditingController(
      text: widget.initialModel?.maxTokens?.toString() ?? '',
    );
    _temperatureController = TextEditingController(
      text: widget.initialModel?.temperature?.toString() ?? '0.7',
    );
    _authScheme = widget.initialModel?.authScheme ?? AiAuthScheme.bearer;
    _protocolType = widget.initialModel?.protocolType ?? AiProtocolType.openai;
    _apiDialect =
        widget.initialModel?.apiDialect ?? inferAiApiDialect(_protocolType);
    _providerKind =
        widget.initialModel?.providerKind ?? inferAiProviderKind(_protocolType);
    _requestMethod = widget.initialModel?.requestMethod ?? 'POST';
    _streamEnabled = widget.initialModel?.streamEnabled ?? true;
    _responsesModelIdController = TextEditingController(
      text: widget.initialModel?.operationRouting.responsesModelId ?? '',
    );
    _embeddingModelIdController = TextEditingController(
      text: widget.initialModel?.operationRouting.embeddingModelId ?? '',
    );
    _moderationModelIdController = TextEditingController(
      text: widget.initialModel?.operationRouting.moderationModelId ?? '',
    );
    _rerankModelIdController = TextEditingController(
      text: widget.initialModel?.operationRouting.rerankModelId ?? '',
    );
    _imageModelIdController = TextEditingController(
      text: widget.initialModel?.operationRouting.imageModelId ?? '',
    );
    _videoModelIdController = TextEditingController(
      text: widget.initialModel?.operationRouting.videoModelId ?? '',
    );
    _speechModelIdController = TextEditingController(
      text: widget.initialModel?.operationRouting.speechModelId ?? '',
    );
    _transcriptionModelIdController = TextEditingController(
      text: widget.initialModel?.operationRouting.transcriptionModelId ?? '',
    );
    _translationModelIdController = TextEditingController(
      text: widget.initialModel?.operationRouting.translationModelId ?? '',
    );
    _realtimeModelIdController = TextEditingController(
      text: widget.initialModel?.operationRouting.realtimeModelId ?? '',
    );
    _defaultVoiceController = TextEditingController(
      text: widget.initialModel?.operationRouting.defaultVoice ?? '',
    );
    _realtimeTransportController = TextEditingController(
      text: widget.initialModel?.realtime.transport ?? '',
    );
    _realtimeUrlOverrideController = TextEditingController(
      text: widget.initialModel?.realtime.urlOverride ?? '',
    );
    _endpointOverridesController = TextEditingController(
      text: _prettyJson(
        aiEndpointOverridesToJson(
          widget.initialModel?.endpointOverrides ??
              const <AiApiFamily, AiEndpointOverride>{},
        ),
      ),
    );
    _operationExtrasController = TextEditingController(
      text: _prettyJson(
        widget.initialModel?.operationExtras ?? const <String, Object?>{},
      ),
    );
    _availableModelIds = AiModelConfig.normalizeModelIds(
      widget.initialModel?.availableModelIds ?? const <String>[],
    );
    _activeModelId = widget.initialModel?.modelId.trim().isNotEmpty == true
        ? widget.initialModel!.modelId.trim()
        : null;
    _modelProfiles = Map<String, AiModelProfile>.of(
      widget.initialModel?.modelProfiles ?? const <String, AiModelProfile>{},
    );
    _customHeaderEntries = <_HeaderEntry>[];
    final existingHeaders =
        widget.initialModel?.customHeaders ?? const <String, String>{};
    for (final entry in existingHeaders.entries) {
      _customHeaderEntries.add(
        _HeaderEntry(
          keyController: TextEditingController(text: entry.key),
          valueController: TextEditingController(text: entry.value),
        ),
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _baseUrlController.dispose();
    _tokenController.dispose();
    _modelIdController.dispose();
    _maxContextTokensController.dispose();
    _manualModelIdController.dispose();
    _maxTokensController.dispose();
    _temperatureController.dispose();
    _responsesModelIdController.dispose();
    _embeddingModelIdController.dispose();
    _moderationModelIdController.dispose();
    _rerankModelIdController.dispose();
    _imageModelIdController.dispose();
    _videoModelIdController.dispose();
    _speechModelIdController.dispose();
    _transcriptionModelIdController.dispose();
    _translationModelIdController.dispose();
    _realtimeModelIdController.dispose();
    _defaultVoiceController.dispose();
    _realtimeTransportController.dispose();
    _realtimeUrlOverrideController.dispose();
    _endpointOverridesController.dispose();
    _operationExtrasController.dispose();
    for (final entry in _customHeaderEntries) {
      entry.keyController.dispose();
      entry.valueController.dispose();
    }
    _chipScrollController.dispose();
    _errorPulse.dispose();
    super.dispose();
  }

  Future<void> _scanModels() async {
    final baseUrl = _baseUrlController.text.trim();
    if (baseUrl.isEmpty || !isValidHttpUrl(baseUrl)) {
      setState(() {
        _scanError = AppLocalizations.of(context)!.mdlEdEnterAValidBaseUrlFirst;
      });
      _errorPulse.value++;
      return;
    }

    setState(() {
      _isScanning = true;
      _scanError = null;
    });

    final scanner = AiModelScanner();
    try {
      final config = AiModelConfig(
        id: '',
        baseUrl: baseUrl,
        authScheme: _authScheme,
        token: _tokenController.text.trim(),
        modelId: '',
        protocolType: _protocolType,
        customHeaders: _collectCustomHeaders(),
      );
      final result = await scanner.scan(config);
      if (!mounted) return;

      if (result.isSuccess) {
        // 2026-05-01: Scan replaces — never diffs. Users explicitly tap
        // "Scan models" to get a fresh authoritative list from the
        // provider; merging with previously cached IDs surfaces stale
        // models that were deprecated upstream and confuses the picker.
        // The freshly scanned list becomes the new source of truth; if
        // the previously active model is missing from it, we drop the
        // active selection rather than keep dangling state.
        final sorted = AiModelConfig.normalizeModelIds(result.modelIds);
        setState(() {
          _availableModelIds = sorted;
          _isScanning = false;
          _scanError = result.modelIds.isEmpty
              ? AppLocalizations.of(context)!.mdlEdNoModelsFoundFromThisProvider
              : null;
          // Reconcile active selection against the freshly scanned list:
          // - If the previously active model is still present, keep it.
          // - Otherwise, fall back to the first scanned model (or null).
          final previousActive = _activeModelId;
          if (previousActive != null && sorted.contains(previousActive)) {
            // Keep selection.
          } else if (sorted.isNotEmpty) {
            _activeModelId = sorted.first;
            _modelIdController.text = sorted.first;
          } else {
            _activeModelId = null;
            _modelIdController.text = '';
          }
        });
      } else {
        setState(() {
          _isScanning = false;
          _scanError = result.error;
        });
        _errorPulse.value++;
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isScanning = false;
        _scanError = '$e';
      });
      _errorPulse.value++;
    } finally {
      scanner.dispose();
    }
  }

  void _addManualModelId() {
    final manualId = _manualModelIdController.text.trim();
    if (manualId.isEmpty) return;
    if (_availableModelIds.contains(manualId)) {
      _manualModelIdController.clear();
      return;
    }
    setState(() {
      _availableModelIds = AiModelConfig.normalizeModelIds(<String>[
        ..._availableModelIds,
        manualId,
      ]);
      _manualModelIdController.clear();
      // If no model was selected, auto-select this one.
      if (_activeModelId == null) {
        _activeModelId = manualId;
        _modelIdController.text = manualId;
      }
    });
  }

  void _removeModelId(String modelId) {
    setState(() {
      _availableModelIds = AiModelConfig.normalizeModelIds(
        _availableModelIds.where((id) => id != modelId),
      );
      _modelProfiles.remove(modelId);
      if (_activeModelId == modelId) {
        _activeModelId = _availableModelIds.isNotEmpty
            ? _availableModelIds.first
            : null;
        _modelIdController.text = _activeModelId ?? '';
      }
    });
  }

  void _selectModelId(String modelId) {
    final trimmedModelId = modelId.trim();
    if (trimmedModelId.isEmpty) {
      return;
    }
    setState(() {
      _activeModelId = trimmedModelId;
      _modelIdController.text = trimmedModelId;
      _availableModelIds = AiModelConfig.normalizeModelIds(<String>[
        ..._availableModelIds,
        trimmedModelId,
      ]);
    });
  }

  Future<void> _editModelProfile(String modelId) async {
    final existing = _modelProfiles[modelId] ?? const AiModelProfile();
    final effectiveModel = AiModelConfig(
      id: widget.initialModel?.id ?? '',
      name: _nameController.text.trim(),
      baseUrl: _baseUrlController.text.trim(),
      authScheme: _authScheme,
      token: _tokenController.text.trim(),
      modelId: modelId,
      protocolType: _protocolType,
      modelProfiles: <String, AiModelProfile>{
        ..._modelProfiles,
        if (existing.hasUserOverrides) modelId: existing,
      },
    );
    final result = await showAnimatedDialog<AiModelProfile>(
      context: context,
      builder: (context) => _ModelProfileEditorDialog(
        modelId: modelId,
        initialProfile: existing,
        effectiveProfile: effectiveModel.profileFor(modelId),
        protocolType: _protocolType,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (result.hasUserOverrides) {
        _modelProfiles[modelId] = result;
      } else {
        _modelProfiles.remove(modelId);
      }
    });
  }

  void _addHeaderEntry() {
    setState(() {
      _customHeaderEntries.add(
        _HeaderEntry(
          keyController: TextEditingController(),
          valueController: TextEditingController(),
        ),
      );
    });
  }

  void _removeHeaderEntry(int index) {
    setState(() {
      final entry = _customHeaderEntries.removeAt(index);
      entry.keyController.dispose();
      entry.valueController.dispose();
    });
  }

  Map<String, String> _collectCustomHeaders() {
    final result = <String, String>{};
    for (final entry in _customHeaderEntries) {
      final key = entry.keyController.text.trim();
      final value = entry.valueController.text.trim();
      if (key.isNotEmpty) {
        result[key] = value;
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: !_isSaving,
      child: Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760, maxHeight: 860),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.initialModel == null
                          ? l10n.aiModelDialogCreateTitle
                          : l10n.aiModelDialogEditTitle,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: SingleChildScrollView(
                        // Disable the macOS trackpad rubber-band / overscroll
                        // elastic effect. Inside a bounded-height modal dialog
                        // the bouncing spring simulation combined with rapid
                        // successive wheel / trackpad events causes the
                        // visible "pull-back / jitter" glitch.
                        physics: const ClampingScrollPhysics(),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TextFormField(
                                controller: _nameController,
                                enabled: !_isSaving,
                                decoration: InputDecoration(
                                  labelText: AppLocalizations.of(
                                    context,
                                  )!.mdlEdProviderName,
                                  hintText: AppLocalizations.of(
                                    context,
                                  )!.mdlEdOptionalEGDeepseekLocalOllama,
                                ),
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _baseUrlController,
                                enabled: !_isSaving,
                                decoration: InputDecoration(
                                  labelText: l10n.aiModelBaseUrl,
                                ),
                                validator: (value) {
                                  final rawValue = value?.trim() ?? '';
                                  if (rawValue.isEmpty) {
                                    return l10n.aiModelBaseUrlRequired;
                                  }
                                  if (!isValidHttpUrl(rawValue)) {
                                    return l10n.aiModelBaseUrlInvalid;
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final stacked = constraints.maxWidth < 640;
                                  final authDropdown =
                                      DropdownButtonFormField<AiAuthScheme>(
                                        initialValue: _authScheme,
                                        decoration: InputDecoration(
                                          labelText: l10n.aiModelAuthScheme,
                                        ),
                                        items: AiAuthScheme.values
                                            .map(
                                              (item) =>
                                                  DropdownMenuItem<
                                                    AiAuthScheme
                                                  >(
                                                    value: item,
                                                    child: Text(
                                                      item.label(l10n),
                                                    ),
                                                  ),
                                            )
                                            .toList(growable: false),
                                        onChanged: _isSaving
                                            ? null
                                            : (value) {
                                                if (value == null) {
                                                  return;
                                                }
                                                setState(() {
                                                  _authScheme = value;
                                                });
                                              },
                                      );
                                  final protocolDropdown =
                                      DropdownButtonFormField<AiProtocolType>(
                                        initialValue: _protocolType,
                                        decoration: InputDecoration(
                                          labelText: l10n.aiModelProtocol,
                                        ),
                                        items: AiProtocolType.values
                                            .map(
                                              (item) =>
                                                  DropdownMenuItem<
                                                    AiProtocolType
                                                  >(
                                                    value: item,
                                                    child: Text(
                                                      item.label(l10n),
                                                    ),
                                                  ),
                                            )
                                            .toList(growable: false),
                                        onChanged: _isSaving
                                            ? null
                                            : (value) {
                                                if (value == null) {
                                                  return;
                                                }
                                                setState(() {
                                                  _protocolType = value;
                                                });
                                              },
                                      );
                                  if (stacked) {
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        authDropdown,
                                        const SizedBox(height: 16),
                                        protocolDropdown,
                                      ],
                                    );
                                  }
                                  return Row(
                                    children: [
                                      Expanded(child: authDropdown),
                                      const SizedBox(width: 16),
                                      Expanded(child: protocolDropdown),
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _tokenController,
                                enabled: !_isSaving,
                                obscureText: _obscureToken,
                                decoration: InputDecoration(
                                  labelText: l10n.aiModelToken,
                                  suffixIconConstraints: const BoxConstraints(
                                    minWidth: 56,
                                    minHeight: 40,
                                  ),
                                  suffixIcon: Padding(
                                    padding: const EdgeInsetsDirectional.only(
                                      end: 10,
                                    ),
                                    child: IconButton(
                                      onPressed: _isSaving
                                          ? null
                                          : () {
                                              setState(() {
                                                _obscureToken = !_obscureToken;
                                              });
                                            },
                                      style: IconButton.styleFrom(
                                        backgroundColor: Colors.transparent,
                                        foregroundColor:
                                            colorScheme.onSurfaceVariant,
                                        disabledForegroundColor: colorScheme
                                            .onSurfaceVariant
                                            .withValues(alpha: 0.38),
                                        minimumSize: const Size(36, 36),
                                        maximumSize: const Size(36, 36),
                                        padding: EdgeInsets.zero,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      icon: Icon(
                                        _obscureToken
                                            ? Icons.visibility_outlined
                                            : Icons.visibility_off_outlined,
                                        size: 22,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                              // ── Model scan section ──
                              Row(
                                children: [
                                  Text(
                                    l10n.aiModelAvailableModels,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleSmall,
                                  ),
                                  const SizedBox(width: 12),
                                  if (_isScanning)
                                    const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  else
                                    FilledButton.tonalIcon(
                                      onPressed: _isSaving ? null : _scanModels,
                                      icon: const Icon(
                                        Icons.radar_rounded,
                                        size: 18,
                                      ),
                                      label: Text(l10n.aiModelScanButton),
                                    ),
                                  if (_isScanning) ...[
                                    const SizedBox(width: 8),
                                    Text(
                                      l10n.aiModelScanning,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ],
                              ),
                              if (_scanError != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  _scanError!,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: colorScheme.error),
                                ),
                              ],
                              const SizedBox(height: 12),
                              // Available models chip list
                              if (_visibleModelIds.isNotEmpty)
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxHeight: 200,
                                  ),
                                  child: RepaintBoundary(
                                    // Swallow overscroll notifications from this
                                    // inner scroll area so they cannot bubble up
                                    // and re-trigger the outer SingleChildScrollView,
                                    // which would cause both scrollables to
                                    // jitter against each other.
                                    child: NotificationListener<OverscrollNotification>(
                                      onNotification: (_) => true,
                                      child: OpenHandSafeScrollbar(
                                        controller: _chipScrollController,
                                        thumbVisibility:
                                            _visibleModelIds.length > 30,
                                        child: SingleChildScrollView(
                                          controller: _chipScrollController,
                                          physics:
                                              const ClampingScrollPhysics(),
                                          child: Wrap(
                                            spacing: 8,
                                            runSpacing: 6,
                                            children: _visibleModelIds
                                                .map((id) {
                                                  final isActive =
                                                      id == _activeModelId;
                                                  return _AiProviderModelChip(
                                                    modelId: id,
                                                    isActive: isActive,
                                                    enabled: !_isSaving,
                                                    hasProfile:
                                                        _modelProfiles[id]
                                                            ?.hasUserOverrides ==
                                                        true,
                                                    tooltip: isActive
                                                        ? AppLocalizations.of(
                                                            context,
                                                          )!.mdlEdCurrentlyActiveModel
                                                        : AppLocalizations.of(
                                                            context,
                                                          )!.mdlEdClickToSetAsActiveModel,
                                                    onPressed: () =>
                                                        _selectModelId(id),
                                                    onEdit: () =>
                                                        _editModelProfile(id),
                                                    onDeleted: () =>
                                                        _removeModelId(id),
                                                  );
                                                })
                                                .toList(growable: false),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                              else
                                Text(
                                  AppLocalizations.of(
                                    context,
                                  )!.mdlEdTapScanModelsToDiscoverModels,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                ),
                              const SizedBox(height: 12),
                              // Manual model ID input
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _manualModelIdController,
                                      enabled: !_isSaving,
                                      decoration: InputDecoration(
                                        labelText: l10n.aiModelManualIdHint,
                                        isDense: true,
                                      ),
                                      onSubmitted: (_) => _addManualModelId(),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  FilledButton.tonal(
                                    onPressed: _isSaving
                                        ? null
                                        : _addManualModelId,
                                    child: Text(l10n.aiModelManualIdAdd),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              // Current active model (legacy field, auto-synced)
                              TextFormField(
                                controller: _modelIdController,
                                enabled: !_isSaving,
                                decoration: InputDecoration(
                                  labelText: AppLocalizations.of(
                                    context,
                                  )!.mdlEdActiveModelId,
                                  helperText: AppLocalizations.of(
                                    context,
                                  )!.mdlEdTheModelUsedForConversationsSelect,
                                ),
                                onChanged: (value) {
                                  setState(() {
                                    _activeModelId = value.trim().isEmpty
                                        ? null
                                        : value.trim();
                                  });
                                },
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _maxContextTokensController,
                                enabled: !_isSaving,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  labelText: AppLocalizations.of(
                                    context,
                                  )!.mdlEdMaxContextTokens,
                                  helperText: AppLocalizations.of(
                                    context,
                                  )!.mdlEdOptionalLimitsTheHistorySliceUsed,
                                ),
                                validator: (value) {
                                  final trimmed = value?.trim() ?? '';
                                  if (trimmed.isEmpty) {
                                    return null;
                                  }
                                  final parsed = int.tryParse(trimmed);
                                  if (parsed == null || parsed <= 0) {
                                    return AppLocalizations.of(
                                      context,
                                    )!.mdlEdEnterAWholeNumberGreaterThan;
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              // ── Request configuration section ──
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final stacked = constraints.maxWidth < 640;
                                  final methodDropdown =
                                      DropdownButtonFormField<String>(
                                        initialValue: _requestMethod,
                                        decoration: InputDecoration(
                                          labelText: AppLocalizations.of(
                                            context,
                                          )!.mdlEdRequestMethod,
                                        ),
                                        items: const <DropdownMenuItem<String>>[
                                          DropdownMenuItem<String>(
                                            value: 'POST',
                                            child: Text('POST'),
                                          ),
                                          DropdownMenuItem<String>(
                                            value: 'GET',
                                            child: Text('GET'),
                                          ),
                                          DropdownMenuItem<String>(
                                            value: 'PUT',
                                            child: Text('PUT'),
                                          ),
                                          DropdownMenuItem<String>(
                                            value: 'PATCH',
                                            child: Text('PATCH'),
                                          ),
                                          DropdownMenuItem<String>(
                                            value: 'DELETE',
                                            child: Text('DELETE'),
                                          ),
                                          DropdownMenuItem<String>(
                                            value: 'HEAD',
                                            child: Text('HEAD'),
                                          ),
                                          DropdownMenuItem<String>(
                                            value: 'OPTIONS',
                                            child: Text('OPTIONS'),
                                          ),
                                        ],
                                        onChanged: _isSaving
                                            ? null
                                            : (value) {
                                                if (value == null) return;
                                                setState(() {
                                                  _requestMethod = value;
                                                });
                                              },
                                      );
                                  final streamToggle = InputDecorator(
                                    decoration: InputDecoration(
                                      labelText: AppLocalizations.of(
                                        context,
                                      )!.mdlEdOutputMode,
                                      border: InputBorder.none,
                                      contentPadding: const EdgeInsets.only(
                                        top: 8,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Text(
                                          _streamEnabled
                                              ? AppLocalizations.of(
                                                  context,
                                                )!.mdlEdStreaming
                                              : AppLocalizations.of(
                                                  context,
                                                )!.mdlEdNonStreaming,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                color: colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                        ),
                                        const Spacer(),
                                        Switch(
                                          value: _streamEnabled,
                                          onChanged: null, // Disabled for now
                                        ),
                                      ],
                                    ),
                                  );
                                  if (stacked) {
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        methodDropdown,
                                        const SizedBox(height: 16),
                                        streamToggle,
                                      ],
                                    );
                                  }
                                  return Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(child: methodDropdown),
                                      const SizedBox(width: 16),
                                      Expanded(child: streamToggle),
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 16),
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final stacked = constraints.maxWidth < 640;
                                  final maxTokensField = TextFormField(
                                    controller: _maxTokensController,
                                    enabled: !_isSaving,
                                    keyboardType: TextInputType.number,
                                    decoration: InputDecoration(
                                      labelText: AppLocalizations.of(
                                        context,
                                      )!.mdlEdMaxOutputTokens,
                                      helperText: AppLocalizations.of(
                                        context,
                                      )!.mdlEdOptionalUsesAdapterDefaultIfUnset,
                                    ),
                                    validator: (value) {
                                      final trimmed = value?.trim() ?? '';
                                      if (trimmed.isEmpty) return null;
                                      final parsed = int.tryParse(trimmed);
                                      if (parsed == null || parsed <= 0) {
                                        return AppLocalizations.of(
                                          context,
                                        )!.mdlEdEnterAWholeNumberGreaterThan;
                                      }
                                      return null;
                                    },
                                  );
                                  final temperatureField = TextFormField(
                                    controller: _temperatureController,
                                    enabled: !_isSaving,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    decoration: InputDecoration(
                                      labelText: AppLocalizations.of(
                                        context,
                                      )!.mdlEdTemperature,
                                      helperText: AppLocalizations.of(
                                        context,
                                      )!.mdlEd0020Default0,
                                    ),
                                    validator: (value) {
                                      final trimmed = value?.trim() ?? '';
                                      if (trimmed.isEmpty) return null;
                                      final parsed = double.tryParse(trimmed);
                                      if (parsed == null ||
                                          parsed < 0 ||
                                          parsed > 2.0) {
                                        return AppLocalizations.of(
                                          context,
                                        )!.mdlEdEnterANumberBetween00;
                                      }
                                      return null;
                                    },
                                  );
                                  if (stacked) {
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        maxTokensField,
                                        const SizedBox(height: 16),
                                        temperatureField,
                                      ],
                                    );
                                  }
                                  return Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(child: maxTokensField),
                                      const SizedBox(width: 16),
                                      Expanded(child: temperatureField),
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 20),
                              Text(
                                '高级接口配置',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 12),
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final stacked = constraints.maxWidth < 640;
                                  final dialectDropdown =
                                      DropdownButtonFormField<AiApiDialect>(
                                        initialValue: _apiDialect,
                                        decoration: const InputDecoration(
                                          labelText: 'API 方言',
                                        ),
                                        items: AiApiDialect.values
                                            .map(
                                              (item) => DropdownMenuItem<
                                                AiApiDialect
                                              >(
                                                value: item,
                                                child: Text(item.storageValue),
                                              ),
                                            )
                                            .toList(growable: false),
                                        onChanged: _isSaving
                                            ? null
                                            : (value) {
                                                if (value == null) return;
                                                setState(() {
                                                  _apiDialect = value;
                                                });
                                              },
                                      );
                                  final providerKindDropdown =
                                      DropdownButtonFormField<AiProviderKind>(
                                        initialValue: _providerKind,
                                        decoration: const InputDecoration(
                                          labelText: '服务商类型',
                                        ),
                                        items: AiProviderKind.values
                                            .map(
                                              (item) => DropdownMenuItem<
                                                AiProviderKind
                                              >(
                                                value: item,
                                                child: Text(item.storageValue),
                                              ),
                                            )
                                            .toList(growable: false),
                                        onChanged: _isSaving
                                            ? null
                                            : (value) {
                                                if (value == null) return;
                                                setState(() {
                                                  _providerKind = value;
                                                });
                                              },
                                      );
                                  if (stacked) {
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        dialectDropdown,
                                        const SizedBox(height: 16),
                                        providerKindDropdown,
                                      ],
                                    );
                                  }
                                  return Row(
                                    children: [
                                      Expanded(child: dialectDropdown),
                                      const SizedBox(width: 16),
                                      Expanded(child: providerKindDropdown),
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 16),
                              TextField(
                                controller: _responsesModelIdController,
                                enabled: !_isSaving,
                                decoration: const InputDecoration(
                                  labelText: 'Responses 模型 ID（可选）',
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _embeddingModelIdController,
                                enabled: !_isSaving,
                                decoration: const InputDecoration(
                                  labelText: 'Embeddings 模型 ID（可选）',
                                ),
                              ),
                              const SizedBox(height: 12),
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final stacked = constraints.maxWidth < 640;
                                  final moderationField = TextField(
                                    controller: _moderationModelIdController,
                                    enabled: !_isSaving,
                                    decoration: const InputDecoration(
                                      labelText: 'Moderations 模型 ID（可选）',
                                    ),
                                  );
                                  final rerankField = TextField(
                                    controller: _rerankModelIdController,
                                    enabled: !_isSaving,
                                    decoration: const InputDecoration(
                                      labelText: 'Rerank 模型 ID（可选）',
                                    ),
                                  );
                                  if (stacked) {
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        moderationField,
                                        const SizedBox(height: 12),
                                        rerankField,
                                      ],
                                    );
                                  }
                                  return Row(
                                    children: [
                                      Expanded(child: moderationField),
                                      const SizedBox(width: 16),
                                      Expanded(child: rerankField),
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 12),
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final stacked = constraints.maxWidth < 640;
                                  final imageField = TextField(
                                    controller: _imageModelIdController,
                                    enabled: !_isSaving,
                                    decoration: const InputDecoration(
                                      labelText: '图像模型 ID（可选）',
                                    ),
                                  );
                                  final videoField = TextField(
                                    controller: _videoModelIdController,
                                    enabled: !_isSaving,
                                    decoration: const InputDecoration(
                                      labelText: '视频模型 ID（可选）',
                                    ),
                                  );
                                  if (stacked) {
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        imageField,
                                        const SizedBox(height: 12),
                                        videoField,
                                      ],
                                    );
                                  }
                                  return Row(
                                    children: [
                                      Expanded(child: imageField),
                                      const SizedBox(width: 16),
                                      Expanded(child: videoField),
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 12),
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final stacked = constraints.maxWidth < 640;
                                  final speechField = TextField(
                                    controller: _speechModelIdController,
                                    enabled: !_isSaving,
                                    decoration: const InputDecoration(
                                      labelText: '语音模型 ID（可选）',
                                    ),
                                  );
                                  final voiceField = TextField(
                                    controller: _defaultVoiceController,
                                    enabled: !_isSaving,
                                    decoration: const InputDecoration(
                                      labelText: '默认 Voice（可选）',
                                    ),
                                  );
                                  if (stacked) {
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        speechField,
                                        const SizedBox(height: 12),
                                        voiceField,
                                      ],
                                    );
                                  }
                                  return Row(
                                    children: [
                                      Expanded(child: speechField),
                                      const SizedBox(width: 16),
                                      Expanded(child: voiceField),
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 12),
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final stacked = constraints.maxWidth < 640;
                                  final transcriptionField = TextField(
                                    controller: _transcriptionModelIdController,
                                    enabled: !_isSaving,
                                    decoration: const InputDecoration(
                                      labelText: 'Transcription 模型 ID（可选）',
                                    ),
                                  );
                                  final translationField = TextField(
                                    controller: _translationModelIdController,
                                    enabled: !_isSaving,
                                    decoration: const InputDecoration(
                                      labelText: 'Translation 模型 ID（可选）',
                                    ),
                                  );
                                  if (stacked) {
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        transcriptionField,
                                        const SizedBox(height: 12),
                                        translationField,
                                      ],
                                    );
                                  }
                                  return Row(
                                    children: [
                                      Expanded(child: transcriptionField),
                                      const SizedBox(width: 16),
                                      Expanded(child: translationField),
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 12),
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final stacked = constraints.maxWidth < 640;
                                  final realtimeTransportField = TextField(
                                    controller: _realtimeTransportController,
                                    enabled: !_isSaving,
                                    decoration: const InputDecoration(
                                      labelText: 'Realtime Transport（可选）',
                                    ),
                                  );
                                  final realtimeUrlField = TextField(
                                    controller: _realtimeUrlOverrideController,
                                    enabled: !_isSaving,
                                    decoration: const InputDecoration(
                                      labelText: 'Realtime URL Override（可选）',
                                    ),
                                  );
                                  final realtimeModelField = TextField(
                                    controller: _realtimeModelIdController,
                                    enabled: !_isSaving,
                                    decoration: const InputDecoration(
                                      labelText: 'Realtime 模型 ID（可选）',
                                    ),
                                  );
                                  if (stacked) {
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        realtimeTransportField,
                                        const SizedBox(height: 12),
                                        realtimeUrlField,
                                        const SizedBox(height: 12),
                                        realtimeModelField,
                                      ],
                                    );
                                  }
                                  return Column(
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(child: realtimeTransportField),
                                          const SizedBox(width: 16),
                                          Expanded(child: realtimeUrlField),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      realtimeModelField,
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _endpointOverridesController,
                                enabled: !_isSaving,
                                minLines: 4,
                                maxLines: 8,
                                decoration: const InputDecoration(
                                  labelText: 'Endpoint Overrides JSON（可选）',
                                  helperText:
                                      '按 family 自定义 path/url/method/transport/headers/query_defaults。',
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _operationExtrasController,
                                enabled: !_isSaving,
                                minLines: 4,
                                maxLines: 8,
                                decoration: const InputDecoration(
                                  labelText: 'Operation Extras JSON（可选）',
                                  helperText:
                                      '放置 responses/realtime/视频等操作的 provider-specific 扩展参数。',
                                ),
                              ),
                              const SizedBox(height: 20),
                              // ── Custom headers section ──
                              Row(
                                children: [
                                  Text(
                                    AppLocalizations.of(
                                      context,
                                    )!.mdlEdCustomHeaders,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleSmall,
                                  ),
                                  const Spacer(),
                                  FilledButton.tonalIcon(
                                    onPressed: _isSaving
                                        ? null
                                        : _addHeaderEntry,
                                    icon: const Icon(Icons.add, size: 18),
                                    label: Text(
                                      AppLocalizations.of(context)!.mdlEdAdd,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (_customHeaderEntries.isEmpty)
                                Text(
                                  AppLocalizations.of(
                                    context,
                                  )!.mdlEdNoCustomHeadersTapAddTo,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                )
                              else
                                ..._customHeaderEntries.asMap().entries.map((
                                  mapEntry,
                                ) {
                                  final index = mapEntry.key;
                                  final entry = mapEntry.value;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          flex: 2,
                                          child: TextField(
                                            controller: entry.keyController,
                                            enabled: !_isSaving,
                                            decoration: InputDecoration(
                                              labelText: AppLocalizations.of(
                                                context,
                                              )!.mdlEdHeaderName,
                                              isDense: true,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          flex: 3,
                                          child: TextField(
                                            controller: entry.valueController,
                                            enabled: !_isSaving,
                                            decoration: InputDecoration(
                                              labelText: AppLocalizations.of(
                                                context,
                                              )!.mdlEdHeaderValue,
                                              isDense: true,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        IconButton(
                                          onPressed: _isSaving
                                              ? null
                                              : () => _removeHeaderEntry(index),
                                          icon: const Icon(
                                            Icons.close,
                                            size: 18,
                                          ),
                                          style: IconButton.styleFrom(
                                            minimumSize: const Size(32, 32),
                                            maximumSize: const Size(32, 32),
                                            padding: EdgeInsets.zero,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                              if (_errorMessage != null) ...[
                                const SizedBox(height: 16),
                                Text(
                                  _errorMessage!,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(color: colorScheme.error),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (_isSaving) ...[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        OpenHandDialogActionButton.secondary(
                          onPressed: _isSaving
                              ? null
                              : () => Navigator.of(context).pop(false),
                          label: l10n.commonCancel,
                        ),
                        const SizedBox(width: 12),
                        OpenHandDialogActionButton.primary(
                          onPressed: _isSaving ? null : _handleSave,
                          label: l10n.commonSave,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: HighlightPulse(
                    signal: _errorPulse,
                    color: OpenHandStatusColors.error,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleSave() async {
    final l10n = AppLocalizations.of(context)!;
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final model = AiModelConfig(
      id:
          widget.initialModel?.id ??
          context.read<SettingsController>().createAiModelId(),
      name: _nameController.text.trim(),
      baseUrl: _baseUrlController.text.trim(),
      authScheme: _authScheme,
      token: _tokenController.text.trim(),
      modelId: _modelIdController.text.trim(),
      protocolType: _protocolType,
      apiDialect: _apiDialect,
      providerKind: _providerKind,
      maxContextTokens: _parseOptionalPositiveInt(
        _maxContextTokensController.text,
      ),
      availableModelIds: _availableModelIds,
      customHeaders: _collectCustomHeaders(),
      requestMethod: _requestMethod,
      maxTokens: _parseOptionalPositiveInt(_maxTokensController.text),
      temperature: _parseOptionalDouble(_temperatureController.text),
      streamEnabled: _streamEnabled,
      modelProfiles: _modelProfiles,
      operationRouting: AiOperationRouting(
        responsesModelId: _normalizeOptionalText(
          _responsesModelIdController.text,
        ),
        embeddingModelId: _normalizeOptionalText(
          _embeddingModelIdController.text,
        ),
        moderationModelId: _normalizeOptionalText(
          _moderationModelIdController.text,
        ),
        rerankModelId: _normalizeOptionalText(_rerankModelIdController.text),
        imageModelId: _normalizeOptionalText(_imageModelIdController.text),
        videoModelId: _normalizeOptionalText(_videoModelIdController.text),
        speechModelId: _normalizeOptionalText(_speechModelIdController.text),
        transcriptionModelId: _normalizeOptionalText(
          _transcriptionModelIdController.text,
        ),
        translationModelId: _normalizeOptionalText(
          _translationModelIdController.text,
        ),
        realtimeModelId: _normalizeOptionalText(
          _realtimeModelIdController.text,
        ),
        defaultVoice: _normalizeOptionalText(_defaultVoiceController.text),
      ),
      endpointOverrides: parseAiEndpointOverrides(
        _decodeJsonObject(_endpointOverridesController.text),
      ),
      operationExtras: _decodeJsonObject(_operationExtrasController.text),
      realtime: AiRealtimeConfig(
        transport: _normalizeOptionalText(_realtimeTransportController.text),
        urlOverride: _normalizeOptionalText(
          _realtimeUrlOverrideController.text,
        ),
      ),
    );

    late final bool saved;
    try {
      saved = await context.read<SettingsController>().saveAiModel(model);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSaving = false;
        _errorMessage = l10n.settingsPersistenceSaveFailedBody;
      });
      _errorPulse.value++;
      return;
    }
    if (!mounted) {
      return;
    }
    if (!saved) {
      setState(() {
        _isSaving = false;
        _errorMessage = l10n.settingsPersistenceSaveFailedBody;
      });
      _errorPulse.value++;
      return;
    }
    Navigator.of(context).pop(true);
  }

  int? _parseOptionalPositiveInt(String rawValue) {
    final parsed = int.tryParse(rawValue.trim());
    if (parsed == null || parsed <= 0) {
      return null;
    }
    return parsed;
  }

  double? _parseOptionalDouble(String rawValue) {
    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) return null;
    return double.tryParse(trimmed);
  }

  String? _normalizeOptionalText(String rawValue) {
    final trimmed = rawValue.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Map<String, Object?> _decodeJsonObject(String rawValue) {
    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) {
      return const <String, Object?>{};
    }
    final decoded = jsonDecode(trimmed);
    if (decoded is Map<String, Object?>) {
      return Map<String, Object?>.from(decoded);
    }
    if (decoded is Map) {
      return Map<String, Object?>.from(decoded);
    }
    throw const FormatException('Expected a JSON object.');
  }

  String _prettyJson(Map<String, Object?> map) {
    if (map.isEmpty) return '';
    return const JsonEncoder.withIndent('  ').convert(map);
  }
}

class _HeaderEntry {
  _HeaderEntry({required this.keyController, required this.valueController});

  final TextEditingController keyController;
  final TextEditingController valueController;
}

// ─────────────────────────────────────────────────────────────────────────────
// Per-model profile editor dialog
// ─────────────────────────────────────────────────────────────────────────────

class _ModelProfileEditorDialog extends StatefulWidget {
  const _ModelProfileEditorDialog({
    required this.modelId,
    required this.initialProfile,
    required this.effectiveProfile,
    required this.protocolType,
  });

  final String modelId;
  final AiModelProfile initialProfile;
  final AiModelProfile effectiveProfile;
  final AiProtocolType protocolType;

  @override
  State<_ModelProfileEditorDialog> createState() =>
      _ModelProfileEditorDialogState();
}

class _ModelProfileEditorDialogState extends State<_ModelProfileEditorDialog> {
  late final TextEditingController _displayNameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _maxContextLengthController;
  late final TextEditingController _maxSummaryLengthController;
  late final TextEditingController _maxOutputLengthController;
  late final TextEditingController _maxThinkingLengthController;
  late final TextEditingController _inputUsdPer1MController;
  late final TextEditingController _outputUsdPer1MController;
  late final TextEditingController _cacheReadUsdPer1MController;
  late final TextEditingController _cacheWriteUsdPer1MController;
  late final TextEditingController _canonicalSlugController;
  late final TextEditingController _huggingFaceIdController;
  late final TextEditingController _knowledgeCutoffController;
  late final TextEditingController _expirationDateController;
  bool? _isMultimodal;
  bool? _supportsAttachments;
  bool? _requiresReasoningEcho;
  late Set<AiModelModality> _supportedModalities;
  late Set<AiModelCapability> _capabilities;

  @override
  void initState() {
    super.initState();
    final p = widget.initialProfile;
    final effective = widget.effectiveProfile;
    final hasExisting = p.hasUserOverrides;

    // Display name: pre-fill with model ID when creating a fresh profile.
    _displayNameController = TextEditingController(
      text:
          p.displayName ??
          effective.displayName ??
          (hasExisting ? '' : widget.modelId),
    );
    _descriptionController = TextEditingController(
      text: p.description ?? effective.description ?? '',
    );
    _maxContextLengthController = TextEditingController(
      text:
          p.maxContextLength?.toString() ??
          effective.maxContextLength?.toString() ??
          '',
    );
    _maxSummaryLengthController = TextEditingController(
      text:
          p.maxSummaryLength?.toString() ??
          effective.maxSummaryLength?.toString() ??
          '',
    );
    _maxOutputLengthController = TextEditingController(
      text:
          p.maxOutputLength?.toString() ??
          effective.maxOutputLength?.toString() ??
          '',
    );
    _maxThinkingLengthController = TextEditingController(
      text:
          p.maxThinkingLength?.toString() ??
          effective.maxThinkingLength?.toString() ??
          '',
    );
    _inputUsdPer1MController = TextEditingController(
      text:
          p.inputUsdPer1M?.toString() ??
          effective.inputUsdPer1M?.toString() ??
          '',
    );
    _outputUsdPer1MController = TextEditingController(
      text:
          p.outputUsdPer1M?.toString() ??
          effective.outputUsdPer1M?.toString() ??
          '',
    );
    _cacheReadUsdPer1MController = TextEditingController(
      text:
          p.cacheReadUsdPer1M?.toString() ??
          effective.cacheReadUsdPer1M?.toString() ??
          '',
    );
    _cacheWriteUsdPer1MController = TextEditingController(
      text:
          p.cacheWriteUsdPer1M?.toString() ??
          effective.cacheWriteUsdPer1M?.toString() ??
          '',
    );
    _canonicalSlugController = TextEditingController(
      text: p.canonicalSlug ?? effective.canonicalSlug ?? '',
    );
    _huggingFaceIdController = TextEditingController(
      text: p.huggingFaceId ?? effective.huggingFaceId ?? '',
    );
    _knowledgeCutoffController = TextEditingController(
      text: p.knowledgeCutoff ?? effective.knowledgeCutoff ?? '',
    );
    _expirationDateController = TextEditingController(
      text: p.expirationDate ?? effective.expirationDate ?? '',
    );

    if (hasExisting) {
      // User already configured — use their saved values.
      _isMultimodal = p.isMultimodal;
      _supportsAttachments = p.supportsAttachments;
      _requiresReasoningEcho = p.requiresReasoningEcho;
      _supportedModalities = Set<AiModelModality>.of(
        p.supportedModalities.isNotEmpty
            ? p.supportedModalities
            : effective.supportedModalities,
      );
      _capabilities = Set<AiModelCapability>.of(
        p.capabilities.isNotEmpty ? p.capabilities : effective.capabilities,
      );
    } else {
      // Fresh profile — try catalog first, fall back to heuristic inference.
      final catalog = AiModelCatalog.lookup(
        widget.modelId,
        widget.protocolType,
      );
      if (catalog != null) {
        _displayNameController.text = catalog.displayName ?? widget.modelId;
        _descriptionController.text = catalog.description ?? '';
        _isMultimodal = catalog.isMultimodal;
        _supportsAttachments = catalog.supportsAttachments;
        _requiresReasoningEcho = catalog.requiresReasoningEcho;
        _supportedModalities = Set<AiModelModality>.of(
          catalog.supportedModalities,
        );
        _capabilities = Set<AiModelCapability>.of(catalog.capabilities);
        if (catalog.maxContextLength != null) {
          _maxContextLengthController.text = catalog.maxContextLength
              .toString();
        }
        if (catalog.maxOutputLength != null) {
          _maxOutputLengthController.text = catalog.maxOutputLength.toString();
        }
        if (catalog.maxThinkingLength != null) {
          _maxThinkingLengthController.text = catalog.maxThinkingLength
              .toString();
        }
        _canonicalSlugController.text = catalog.canonicalSlug ?? '';
        _huggingFaceIdController.text = catalog.huggingFaceId ?? '';
        _knowledgeCutoffController.text = catalog.knowledgeCutoff ?? '';
        _expirationDateController.text = catalog.expirationDate ?? '';
      } else {
        _isMultimodal = null; // auto-detect
        _supportsAttachments = null; // auto-detect
        _requiresReasoningEcho = null; // fallback to runtime heuristics
        _supportedModalities = _inferModalities();
        _capabilities = _inferCapabilities();
      }
    }
  }

  /// Infer modalities from protocol type + model ID patterns.
  Set<AiModelModality> _inferModalities() {
    // All models support text.
    final result = <AiModelModality>{AiModelModality.text};
    // Check if this model is likely to support image input (vision).
    // Build a temporary AiModelConfig to query the adapter registry.
    final probeConfig = AiModelConfig(
      id: '',
      baseUrl: '',
      authScheme: AiAuthScheme.bearer,
      token: '',
      modelId: widget.modelId,
      protocolType: widget.protocolType,
    );
    if (AiProtocolRegistry.supportsInlineImages(probeConfig)) {
      result.add(AiModelModality.image);
    }
    return result;
  }

  /// Infer generation capabilities from protocol-level rules.
  Set<AiModelCapability> _inferCapabilities() {
    final result = <AiModelCapability>{};
    if (AiImageGenerationService.supportsImageGeneration(widget.protocolType)) {
      result.add(AiModelCapability.imageGeneration);
    }
    if (AiImageGenerationService.supportsVideoGeneration(widget.protocolType)) {
      result.add(AiModelCapability.videoGeneration);
    }
    if (AiImageGenerationService.supportsAudioGeneration(widget.protocolType)) {
      result.add(AiModelCapability.audioGeneration);
    }
    return result;
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _descriptionController.dispose();
    _maxContextLengthController.dispose();
    _maxSummaryLengthController.dispose();
    _maxOutputLengthController.dispose();
    _maxThinkingLengthController.dispose();
    _inputUsdPer1MController.dispose();
    _outputUsdPer1MController.dispose();
    _cacheReadUsdPer1MController.dispose();
    _cacheWriteUsdPer1MController.dispose();
    _canonicalSlugController.dispose();
    _huggingFaceIdController.dispose();
    _knowledgeCutoffController.dispose();
    _expirationDateController.dispose();
    super.dispose();
  }

  int? _parsePositiveInt(String value) {
    final parsed = int.tryParse(value.trim());
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  double? _parseNonNegativeDouble(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final parsed = double.tryParse(trimmed);
    if (parsed == null || !parsed.isFinite || parsed.isNaN || parsed < 0) {
      return null;
    }
    return parsed;
  }

  void _save() {
    final profile = AiModelProfile(
      displayName: _displayNameController.text.trim().isNotEmpty
          ? _displayNameController.text.trim()
          : null,
      description: _descriptionController.text.trim().isNotEmpty
          ? _descriptionController.text.trim()
          : null,
      isMultimodal: _isMultimodal,
      supportedModalities: _supportedModalities,
      maxContextLength: _parsePositiveInt(_maxContextLengthController.text),
      maxSummaryLength: _parsePositiveInt(_maxSummaryLengthController.text),
      maxOutputLength: _parsePositiveInt(_maxOutputLengthController.text),
      maxThinkingLength: _parsePositiveInt(_maxThinkingLengthController.text),
      requiresReasoningEcho: _requiresReasoningEcho,
      capabilities: _capabilities,
      supportsAttachments: _supportsAttachments,
      inputUsdPer1M: _parseNonNegativeDouble(_inputUsdPer1MController.text),
      outputUsdPer1M: _parseNonNegativeDouble(_outputUsdPer1MController.text),
      cacheReadUsdPer1M: _parseNonNegativeDouble(
        _cacheReadUsdPer1MController.text,
      ),
      cacheWriteUsdPer1M: _parseNonNegativeDouble(
        _cacheWriteUsdPer1MController.text,
      ),
      canonicalSlug: _canonicalSlugController.text.trim().isNotEmpty
          ? _canonicalSlugController.text.trim()
          : null,
      huggingFaceId: _huggingFaceIdController.text.trim().isNotEmpty
          ? _huggingFaceIdController.text.trim()
          : null,
      knowledgeCutoff: _knowledgeCutoffController.text.trim().isNotEmpty
          ? _knowledgeCutoffController.text.trim()
          : null,
      expirationDate: _expirationDateController.text.trim().isNotEmpty
          ? _expirationDateController.text.trim()
          : null,
    );
    Navigator.of(context).pop(profile);
  }

  void _reset() {
    Navigator.of(context).pop(const AiModelProfile());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return AlertDialog(
      actionsAlignment: MainAxisAlignment.center,
      actionsOverflowAlignment: OverflowBarAlignment.center,
      title: Text(
        AppLocalizations.of(context)!.mdlEdEditModelProfile,
        style: theme.textTheme.titleMedium,
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          // Use clamping physics to avoid macOS trackpad rubber-band
          // overscroll, which inside a modal AlertDialog presents as a
          // "pull-back / shake" jitter when the user rapidly scrolls to
          // either edge.
          physics: const ClampingScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Model ID (read-only)
              Text(
                widget.modelId,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),

              // Display name
              TextField(
                controller: _displayNameController,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.mdlEdDisplayName,
                  hintText: AppLocalizations.of(
                    context,
                  )!.mdlEdOptionalShownInTheUi,
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),

              // Description
              TextField(
                controller: _descriptionController,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.mdlEdDescription,
                  isDense: true,
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),

              // Multimodal toggle (tri-state)
              _buildSectionHeader(
                AppLocalizations.of(context)!.mdlEdMultimodalSupport,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: <Widget>[
                  ChoiceChip(
                    label: Text(AppLocalizations.of(context)!.mdlEdAutoDetect),
                    selected: _isMultimodal == null,
                    onSelected: (_) => setState(() => _isMultimodal = null),
                  ),
                  ChoiceChip(
                    label: Text(AppLocalizations.of(context)!.mdlEdYes),
                    selected: _isMultimodal == true,
                    onSelected: (_) => setState(() => _isMultimodal = true),
                  ),
                  ChoiceChip(
                    label: Text(AppLocalizations.of(context)!.mdlEdNo),
                    selected: _isMultimodal == false,
                    onSelected: (_) => setState(() => _isMultimodal = false),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Supports attachments toggle (tri-state). Drives whether the
              // composer's attachment button is enabled for sessions using
              // this model.
              _buildSectionHeader(
                AppLocalizations.of(context)!.mdlEdSupportsAttachments,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: <Widget>[
                  ChoiceChip(
                    label: Text(AppLocalizations.of(context)!.mdlEdAutoDetect),
                    selected: _supportsAttachments == null,
                    onSelected: (_) =>
                        setState(() => _supportsAttachments = null),
                  ),
                  ChoiceChip(
                    label: Text(AppLocalizations.of(context)!.mdlEdYes),
                    selected: _supportsAttachments == true,
                    onSelected: (_) =>
                        setState(() => _supportsAttachments = true),
                  ),
                  ChoiceChip(
                    label: Text(AppLocalizations.of(context)!.mdlEdNo),
                    selected: _supportsAttachments == false,
                    onSelected: (_) =>
                        setState(() => _supportsAttachments = false),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              _buildSectionHeader(
                AppLocalizations.of(context)!.mdlEdReasoningEcho,
              ),
              const SizedBox(height: 8),
              Text(
                AppLocalizations.of(context)!.mdlEdReasoningEchoHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: <Widget>[
                  ChoiceChip(
                    label: Text(AppLocalizations.of(context)!.mdlEdAutoDetect),
                    selected: _requiresReasoningEcho == null,
                    onSelected: (_) =>
                        setState(() => _requiresReasoningEcho = null),
                  ),
                  ChoiceChip(
                    label: Text(AppLocalizations.of(context)!.mdlEdYes),
                    selected: _requiresReasoningEcho == true,
                    onSelected: (_) =>
                        setState(() => _requiresReasoningEcho = true),
                  ),
                  ChoiceChip(
                    label: Text(AppLocalizations.of(context)!.mdlEdNo),
                    selected: _requiresReasoningEcho == false,
                    onSelected: (_) =>
                        setState(() => _requiresReasoningEcho = false),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Supported modalities
              _buildSectionHeader(
                AppLocalizations.of(context)!.mdlEdSupportedModalities,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: AiModelModality.values
                    .map((m) {
                      final label = switch (m) {
                        AiModelModality.text => AppLocalizations.of(
                          context,
                        )!.mdlEdText,
                        AiModelModality.image => AppLocalizations.of(
                          context,
                        )!.mdlEdImage,
                        AiModelModality.video => AppLocalizations.of(
                          context,
                        )!.mdlEdVideo,
                        AiModelModality.audio => AppLocalizations.of(
                          context,
                        )!.mdlEdAudio,
                        AiModelModality.file => 'File',
                      };
                      return FilterChip(
                        label: Text(label),
                        selected: _supportedModalities.contains(m),
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              _supportedModalities.add(m);
                            } else {
                              _supportedModalities.remove(m);
                            }
                          });
                        },
                      );
                    })
                    .toList(growable: false),
              ),
              const SizedBox(height: 16),

              // Capabilities
              _buildSectionHeader(
                AppLocalizations.of(context)!.mdlEdGenerationCapabilities,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: AiModelCapability.values
                    .map((c) {
                      final label = switch (c) {
                        AiModelCapability.imageGeneration =>
                          AppLocalizations.of(context)!.mdlEdImage,
                        AiModelCapability.videoGeneration =>
                          AppLocalizations.of(context)!.mdlEdVideo,
                        AiModelCapability.audioGeneration =>
                          AppLocalizations.of(context)!.mdlEdAudio,
                        AiModelCapability.pdfGeneration => AppLocalizations.of(
                          context,
                        )!.mdlEdPdf,
                        AiModelCapability.pptGeneration => AppLocalizations.of(
                          context,
                        )!.mdlEdPpt,
                      };
                      return FilterChip(
                        label: Text(label),
                        selected: _capabilities.contains(c),
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              _capabilities.add(c);
                            } else {
                              _capabilities.remove(c);
                            }
                          });
                        },
                      );
                    })
                    .toList(growable: false),
              ),
              const SizedBox(height: 16),

              // Token limits
              _buildSectionHeader(
                AppLocalizations.of(context)!.mdlEdTokenLimits,
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _maxContextLengthController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: AppLocalizations.of(
                          context,
                        )!.mdlEdContextLength,
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _maxSummaryLengthController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: AppLocalizations.of(
                          context,
                        )!.mdlEdSummaryLength,
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _maxOutputLengthController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: AppLocalizations.of(
                          context,
                        )!.mdlEdOutputLength,
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _maxThinkingLengthController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: AppLocalizations.of(
                          context,
                        )!.mdlEdThinkingLength,
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildSectionHeader(
                AppLocalizations.of(context)!.mdlEdTokenPricingUsd1mTokensLeave,
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _inputUsdPer1MController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: AppLocalizations.of(context)!.mdlEdInput,
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _outputUsdPer1MController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: AppLocalizations.of(context)!.mdlEdOutput,
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _cacheReadUsdPer1MController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: AppLocalizations.of(context)!.mdlEdCacheRead,
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _cacheWriteUsdPer1MController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: AppLocalizations.of(
                          context,
                        )!.mdlEdCacheWrite,
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildSectionHeader('OpenRouter Metadata Overrides'),
              const SizedBox(height: 8),
              TextField(
                controller: _canonicalSlugController,
                decoration: const InputDecoration(
                  labelText: 'canonical_slug',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _huggingFaceIdController,
                decoration: const InputDecoration(
                  labelText: 'hugging_face_id',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _knowledgeCutoffController,
                decoration: const InputDecoration(
                  labelText: 'knowledge_cutoff',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _expirationDateController,
                decoration: const InputDecoration(
                  labelText: 'expiration_date',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 16),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: _buildSectionHeader('OpenRouter Raw Metadata'),
                subtitle: Text(
                  'id / canonical_slug / hugging_face_id / created / architecture / supported_parameters / default_parameters / supported_voices / knowledge_cutoff / expiration_date / links',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                children: [
                  const SizedBox(height: 8),
                  SelectionArea(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        _buildReadonlyOpenRouterMetadata(
                          widget.modelId,
                          widget.effectiveProfile,
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          height: 1.45,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        OpenHandDialogActionButton.destructive(
          onPressed: _reset,
          label: AppLocalizations.of(context)!.mdlEdReset,
        ),
        OpenHandDialogActionButton.secondary(
          onPressed: () => Navigator.of(context).pop(),
          label: AppLocalizations.of(context)!.mdlEdCancel,
        ),
        OpenHandDialogActionButton.primary(
          onPressed: _save,
          label: AppLocalizations.of(context)!.mdlEdOk,
        ),
      ],
    );
  }

  String _buildReadonlyOpenRouterMetadata(
    String modelId,
    AiModelProfile profile,
  ) {
    final map = <String, Object?>{
      'id': modelId,
      'canonical_slug': profile.canonicalSlug,
      'hugging_face_id': profile.huggingFaceId,
      'created': profile.created,
      'architecture': profile.architecture?.toJson(),
      'supported_parameters': profile.supportedParameters,
      'default_parameters': profile.defaultParameters,
      'supported_voices': profile.supportedVoices,
      'knowledge_cutoff': profile.knowledgeCutoff,
      'expiration_date': profile.expirationDate,
      'links': profile.links?.toJson(),
    };
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  Widget _buildSectionHeader(String text) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

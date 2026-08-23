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
  late final TextEditingController _officialWebsiteUrlController;
  late final TextEditingController _baseUrlController;
  late final TextEditingController _tokenController;
  late final TextEditingController _modelIdController;
  late final TextEditingController _modelSearchController;
  late final FocusNode _modelSearchFocusNode;
  late final TextEditingController _maxContextTokensController;
  late final TextEditingController _manualModelIdController;
  late final TextEditingController _maxTokensController;
  late final TextEditingController _temperatureController;
  late AiAuthScheme _authScheme;
  late AiProtocolType _protocolType;
  late AiApiDialect _apiDialect;
  late AiProviderKind _providerKind;
  late String _requestMethod;
  late bool _autoCompleteBaseUrl;
  late bool _streamEnabled;
  late bool _explicitPromptCacheEnabled;
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
  late String _responsesCapabilityStatus;
  late String _realtimeCapabilityStatus;
  late String _filesCapabilityStatus;
  late String _fineTunesCapabilityStatus;
  bool _obscureToken = true;
  bool _modelSearchVisible = false;
  bool _isSaving = false;
  bool _isScanning = false;
  String? _errorMessage;
  String? _scanError;
  final ValueNotifier<int> _errorPulse = ValueNotifier<int>(0);
  List<String> _availableModelIds = const <String>[];
  String? _activeModelId;
  String? _defaultTitleModelId;
  late Map<String, AiModelProfile> _modelProfiles;
  late List<_HeaderEntry> _customHeaderEntries;
  final ScrollController _chipScrollController = ScrollController();
  static const AiEndpointRouter _endpointPreviewRouter = AiEndpointRouter();
  static const double _maxTemperature = 2.0;

  List<String> get _visibleModelIds => AiModelConfig.normalizeModelIds(<String>[
    ..._availableModelIds,
    if ((_activeModelId ?? '').trim().isNotEmpty) _activeModelId!.trim(),
    if ((_defaultTitleModelId ?? '').trim().isNotEmpty)
      _defaultTitleModelId!.trim(),
  ]);

  List<String> get _filteredVisibleModelIds {
    final modelIds = _visibleModelIds;
    if (modelIds.length <= 1) return modelIds;
    return _filterAiModelIds(modelIds, _modelSearchController.text);
  }

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.initialModel?.name ?? '',
    );
    _officialWebsiteUrlController = TextEditingController(
      text: widget.initialModel?.normalizedOfficialWebsiteUrl ?? '',
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
    _modelSearchController = TextEditingController();
    _modelSearchFocusNode = FocusNode();
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
    if (_authScheme == AiAuthScheme.none) {
      _tokenController.clear();
    }
    _protocolType = widget.initialModel?.protocolType ?? AiProtocolType.openai;
    _apiDialect =
        widget.initialModel?.apiDialect ?? inferAiApiDialect(_protocolType);
    _providerKind =
        widget.initialModel?.providerKind ?? inferAiProviderKind(_protocolType);
    _requestMethod = widget.initialModel?.requestMethod ?? 'POST';
    _autoCompleteBaseUrl = widget.initialModel?.autoCompleteBaseUrl ?? true;
    _streamEnabled = widget.initialModel?.streamEnabled ?? true;
    _explicitPromptCacheEnabled =
        widget.initialModel?.explicitPromptCacheEnabled ??
        _defaultExplicitPromptCacheEnabledFor(_protocolType);
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
      text: prettyPrintJson(
        aiEndpointOverridesToJson(
          widget.initialModel?.endpointOverrides ??
              const <AiApiFamily, AiEndpointOverride>{},
        ),
        emptyMapAsBlank: true,
      ),
    );
    _operationExtrasController = TextEditingController(
      text: prettyPrintJson(
        widget.initialModel?.operationExtras ?? const <String, Object?>{},
        emptyMapAsBlank: true,
      ),
    );
    _responsesCapabilityStatus = switch (widget.initialModel
        ?.capabilityStatusFor(AiApiFamily.responses)) {
      'supported' => 'supported',
      'disabled' => 'disabled',
      _ => 'auto',
    };
    _realtimeCapabilityStatus =
        widget.initialModel?.capabilityStatusFor(AiApiFamily.realtime) ??
        'experimental';
    _filesCapabilityStatus =
        widget.initialModel?.capabilityStatusFor(AiApiFamily.files) ??
        'disabled';
    _fineTunesCapabilityStatus =
        widget.initialModel?.capabilityStatusFor(AiApiFamily.fineTunes) ??
        'disabled';
    _availableModelIds = AiModelConfig.normalizeModelIds(
      widget.initialModel?.availableModelIds ?? const <String>[],
    );
    _activeModelId = widget.initialModel?.modelId.trim().isNotEmpty == true
        ? widget.initialModel!.modelId.trim()
        : null;
    _defaultTitleModelId =
        widget.initialModel?.defaultTitleModelId.trim().isNotEmpty == true
        ? widget.initialModel!.defaultTitleModelId.trim()
        : null;
    _modelProfiles = Map<String, AiModelProfile>.of(
      widget.initialModel?.modelProfiles ?? const <String, AiModelProfile>{},
    );
    final legacyGlobalTitleModelId = _legacyGlobalDefaultTitleModelId(
      widget.initialModel,
    );
    if (legacyGlobalTitleModelId != null) {
      final existing =
          _modelProfiles[legacyGlobalTitleModelId] ?? const AiModelProfile();
      _modelProfiles[legacyGlobalTitleModelId] = existing.copyWith(
        isGlobalDefaultTitleModel: true,
      );
    }
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
    _officialWebsiteUrlController.dispose();
    _baseUrlController.dispose();
    _tokenController.dispose();
    _modelIdController.dispose();
    _modelSearchController.dispose();
    _modelSearchFocusNode.dispose();
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

  void _toggleModelSearch() {
    HapticFeedback.selectionClick();
    final nextVisible = !_modelSearchVisible;
    setState(() {
      _modelSearchVisible = nextVisible;
      if (!nextVisible) {
        _modelSearchController.clear();
      }
    });
    if (!nextVisible) {
      _modelSearchFocusNode.unfocus();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _modelSearchVisible) {
        _modelSearchFocusNode.requestFocus();
      }
    });
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
    if (context.read<SettingsController>().isAiModelProviderEndpointBlocked(
      baseUrl,
    )) {
      setState(() {
        _scanError = _aiModelProxyEndpointBlockedMessage(context);
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
        officialWebsiteUrl: _officialWebsiteUrlController.text.trim(),
        baseUrl: baseUrl,
        autoCompleteBaseUrl: _autoCompleteBaseUrl,
        authScheme: _authScheme,
        token: _effectiveToken,
        modelId: '',
        protocolType: _protocolType,
        customHeaders: _collectCustomHeaders(),
      );
      final result = await scanner.scan(config);
      if (!mounted) return;

      if (result.isSuccess) {
        // 手动扫描以服务商当前列表替换缓存，并在下方修正失效选择。
        final sorted = AiModelConfig.normalizeModelIds(result.modelIds);
        setState(() {
          _availableModelIds = sorted;
          _isScanning = false;
          _scanError = result.modelIds.isEmpty
              ? AppLocalizations.of(context)!.mdlEdNoModelsFoundFromThisProvider
              : null;
          // 保留仍存在的当前模型，否则回退到首个扫描结果。
          final previousActive = _activeModelId;
          if (previousActive == null || !sorted.contains(previousActive)) {
            if (sorted.isNotEmpty) {
              _activeModelId = sorted.first;
              _modelIdController.text = sorted.first;
            } else {
              _activeModelId = null;
              _modelIdController.text = '';
            }
          }
          if (_defaultTitleModelId != null &&
              !sorted.contains(_defaultTitleModelId)) {
            _defaultTitleModelId = null;
          }
          if (_visibleModelIds.length <= 1) {
            _modelSearchVisible = false;
            _modelSearchController.clear();
          }
        });
        if (!_modelSearchVisible) {
          _modelSearchFocusNode.unfocus();
        }
      } else {
        setState(() {
          _isScanning = false;
          _scanError = result.error;
        });
        _errorPulse.value++;
      }
    } catch (error, stack) {
      silentLog('settings_ai_model_editor', '扫描 AI 模型', error, stack);
      if (!mounted) return;
      setState(() {
        _isScanning = false;
        _scanError = userFailureMessage(error, fallback: '扫描模型失败，请稍后重试。');
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
      if (_defaultTitleModelId == modelId) {
        _defaultTitleModelId = null;
      }
      if (_visibleModelIds.length <= 1) {
        _modelSearchVisible = false;
        _modelSearchController.clear();
      }
    });
    if (!_modelSearchVisible) {
      _modelSearchFocusNode.unfocus();
    }
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

  void _selectDefaultTitleModelId(String? modelId) {
    final trimmedModelId = modelId?.trim() ?? '';
    setState(() {
      _defaultTitleModelId = trimmedModelId.isEmpty ? null : trimmedModelId;
      if (trimmedModelId.isNotEmpty) {
        _availableModelIds = AiModelConfig.normalizeModelIds(<String>[
          ..._availableModelIds,
          trimmedModelId,
        ]);
      }
    });
  }

  String? _legacyGlobalDefaultTitleModelId(AiModelConfig? model) {
    if (model?.isGlobalDefaultTitleModel != true) {
      return null;
    }
    final providerDefaultModelId = model!.defaultTitleModelId.trim();
    if (providerDefaultModelId.isNotEmpty) {
      return providerDefaultModelId;
    }
    final activeModelId = model.modelId.trim();
    return activeModelId.isEmpty ? null : activeModelId;
  }

  Future<void> _editModelProfile(String modelId) async {
    try {
      await OpenRouterModelProfileStore.instance.ensureLoaded();
    } catch (_) {
      // 缓存不可用时继续使用内置目录和已有显式配置。
    }
    if (!mounted) return;
    final existing = _modelProfiles[modelId] ?? const AiModelProfile();
    final effectiveModel = AiModelConfig(
      id: widget.initialModel?.id ?? '',
      name: _nameController.text.trim(),
      baseUrl: _baseUrlController.text.trim(),
      officialWebsiteUrl: _officialWebsiteUrlController.text.trim(),
      autoCompleteBaseUrl: _autoCompleteBaseUrl,
      authScheme: _authScheme,
      token: _effectiveToken,
      modelId: modelId,
      protocolType: _protocolType,
      modelProfiles: <String, AiModelProfile>{
        ..._modelProfiles,
        if (existing.hasUserOverrides) modelId: existing,
      },
    );
    final result = await showAnimatedDialog<_ModelProfileEditorResult>(
      context: context,
      builder: (context) => _ModelProfileEditorDialog(
        modelId: modelId,
        existingModelIds: _visibleModelIds,
        initialProfile: existing,
        effectiveProfile: effectiveModel.profileFor(modelId),
        protocolType: _protocolType,
        onDuplicate: _duplicateModelProfile,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _applyModelProfileResult(modelId, result);
    });
  }

  void _applyModelProfileResult(
    String originalModelId,
    _ModelProfileEditorResult result,
  ) {
    final nextModelId = result.modelId.trim();
    if (nextModelId.isEmpty) {
      return;
    }
    if (nextModelId != originalModelId) {
      _availableModelIds = AiModelConfig.normalizeModelIds(<String>[
        ..._availableModelIds.where((id) => id != originalModelId),
        nextModelId,
      ]);
      _modelProfiles.remove(originalModelId);
      if (_activeModelId == originalModelId) {
        _activeModelId = nextModelId;
        _modelIdController.text = nextModelId;
      }
      if (_defaultTitleModelId == originalModelId) {
        _defaultTitleModelId = nextModelId;
      }
      _replaceRoutingModelId(originalModelId, nextModelId);
    }

    final nextProfiles = <String, AiModelProfile>{};
    for (final entry in _modelProfiles.entries) {
      var profile = entry.value;
      if (result.profile.isGlobalDefaultTitleModel &&
          entry.key != nextModelId &&
          profile.isGlobalDefaultTitleModel) {
        profile = profile.copyWith(isGlobalDefaultTitleModel: false);
      }
      if (profile.hasUserOverrides) {
        nextProfiles[entry.key] = profile;
      }
    }
    if (result.profile.hasUserOverrides) {
      nextProfiles[nextModelId] = result.profile;
    } else {
      nextProfiles.remove(nextModelId);
    }
    _modelProfiles = nextProfiles;
  }

  String _duplicateModelProfile(String sourceModelId, AiModelProfile profile) {
    final copyModelId = _nextCopyModelId(sourceModelId);
    final copiedProfile = profile.copyWith(isGlobalDefaultTitleModel: false);
    setState(() {
      _availableModelIds = AiModelConfig.normalizeModelIds(<String>[
        ..._availableModelIds,
        copyModelId,
      ]);
      final nextProfiles = <String, AiModelProfile>{};
      for (final entry in _modelProfiles.entries) {
        if (entry.value.hasUserOverrides) {
          nextProfiles[entry.key] = entry.value;
        }
      }
      if (copiedProfile.hasUserOverrides) {
        nextProfiles[copyModelId] = copiedProfile;
      }
      _modelProfiles = nextProfiles;
    });
    return copyModelId;
  }

  String _nextCopyModelId(String sourceModelId) {
    final base = sourceModelId.trim().isEmpty ? 'model' : sourceModelId.trim();
    final used = _visibleModelIds.toSet();
    for (var index = 1; index <= 9999; index++) {
      final candidate = AiOneMillionContextPolicy.copyModelId(base, index);
      if (!used.contains(candidate)) {
        return candidate;
      }
    }
    return AiOneMillionContextPolicy.copyModelId(
      base,
      DateTime.now().microsecondsSinceEpoch,
    );
  }

  void _replaceRoutingModelId(String oldModelId, String nextModelId) {
    void replace(TextEditingController controller) {
      if (controller.text.trim() == oldModelId) {
        controller.text = nextModelId;
      }
    }

    replace(_responsesModelIdController);
    replace(_embeddingModelIdController);
    replace(_moderationModelIdController);
    replace(_rerankModelIdController);
    replace(_imageModelIdController);
    replace(_videoModelIdController);
    replace(_speechModelIdController);
    replace(_transcriptionModelIdController);
    replace(_translationModelIdController);
    replace(_realtimeModelIdController);
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

  bool get _showsExplicitPromptCacheControl =>
      _protocolType == AiProtocolType.claude;

  bool get _usesTokenAuth => _authScheme != AiAuthScheme.none;

  String get _effectiveToken =>
      _usesTokenAuth ? _tokenController.text.trim() : '';

  Map<String, Object?> _tryDecodeJsonObject(String rawValue) {
    try {
      return _decodeJsonObject(rawValue);
    } catch (_) {
      return const <String, Object?>{};
    }
  }

  ({String responses, String chat}) _previewChatEndpoints() {
    final baseUrl = _baseUrlController.text.trim();
    if (baseUrl.isEmpty || !isValidHttpUrl(baseUrl)) {
      return (responses: '', chat: '');
    }
    try {
      final adapter = AiProtocolRegistry.adapterFor(_protocolType);
      final config = AiModelConfig(
        id: widget.initialModel?.id ?? '',
        name: _nameController.text.trim(),
        baseUrl: baseUrl,
        autoCompleteBaseUrl: _autoCompleteBaseUrl,
        authScheme: _authScheme,
        token: _effectiveToken,
        modelId: _modelIdController.text.trim(),
        protocolType: _protocolType,
        apiDialect: _apiDialect,
        providerKind: _providerKind,
        customHeaders: _collectCustomHeaders(),
        requestMethod: _requestMethod,
        operationRouting: AiOperationRouting(
          responsesModelId: nullIfBlank(_responsesModelIdController.text),
        ),
        endpointOverrides: parseAiEndpointOverrides(
          _tryDecodeJsonObject(_endpointOverridesController.text),
        ),
      );
      final chat = _endpointPreviewRouter
          .resolve(
            config,
            adapter.operationFamily,
            fallbackPath: adapter.endpointPath,
            method: _requestMethod,
          )
          .url;
      final responses =
          _apiDialect == AiApiDialect.openAiCompat &&
              _responsesCapabilityStatus != 'disabled'
          ? _endpointPreviewRouter
                .resolve(config, AiApiFamily.responses, method: _requestMethod)
                .url
          : '';
      return (responses: responses, chat: chat);
    } catch (_) {
      return (responses: '', chat: '');
    }
  }

  Widget _buildAutoCompleteBaseUrlControl() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final duration = openHandMotionDuration(context, kOpenHandMotion180);
    final preview = _previewChatEndpoints();
    final usesResponsesRouting = _apiDialect == AiApiDialect.openAiCompat;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(0, 0, 0, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      openHandLocalizedText(
                        context,
                        zh: '自动补全 Base URL',
                        en: 'Auto-complete Base URL',
                      ),
                      style: theme.textTheme.titleSmall,
                    ),
                    kOpenHandGap4,
                    Text(
                      _autoCompleteBaseUrl
                          ? openHandLocalizedText(
                              context,
                              zh: '开启时按协议补默认版本路径，例如 OpenAI 兼容接口会追加 v1。',
                              en: 'Adds the protocol default version path, such as v1 for OpenAI-compatible endpoints.',
                            )
                          : openHandLocalizedText(
                              context,
                              zh: '关闭时严格使用你填写的 Base URL，只继续拼接资源路径。',
                              en: 'Uses the Base URL exactly, then appends only the resource path.',
                            ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              kOpenHandHGap16,
              Switch(
                value: _autoCompleteBaseUrl,
                onChanged: _isSaving
                    ? null
                    : (value) {
                        setState(() {
                          _autoCompleteBaseUrl = value;
                        });
                      },
              ),
            ],
          ),
          AnimatedSize(
            duration: duration,
            curve: kOpenHandSwitchInCurve,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: duration,
              switchInCurve: kOpenHandSwitchInCurve,
              switchOutCurve: kOpenHandSwitchOutCurve,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SizeTransition(
                  sizeFactor: animation,
                  axisAlignment: -1,
                  child: child,
                ),
              ),
              child: preview.chat.isEmpty
                  ? const SizedBox.shrink(
                      key: ValueKey<String>('endpoint-preview-empty'),
                    )
                  : Container(
                      key: ValueKey<String>(
                        '$usesResponsesRouting|${preview.responses}|${preview.chat}',
                      ),
                      width: double.infinity,
                      margin: const EdgeInsets.only(top: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer.withValues(
                          alpha: 0.22,
                        ),
                        borderRadius: kOpenHandBorderRadius14,
                        border: Border.all(
                          color: colorScheme.primary.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            usesResponsesRouting
                                ? preview.responses.isNotEmpty
                                      ? _responsesCapabilityStatus ==
                                                'supported'
                                            ? openHandLocalizedText(
                                                context,
                                                zh: '已验证 Responses，运行时直接使用该接口。',
                                                zhHant:
                                                    '已驗證 Responses，執行時直接使用該介面。',
                                                en: 'Responses is verified and used directly at runtime.',
                                                fr: 'Responses est vérifié et utilisé directement.',
                                                de: 'Responses ist verifiziert und wird direkt verwendet.',
                                                ja: 'Responses は検証済みで、実行時に直接使用されます。',
                                              )
                                            : openHandLocalizedText(
                                                context,
                                                zh: '尚未固定接口；先尝试 Responses，确认不兼容后转 Chat Completions。',
                                                zhHant:
                                                    '尚未固定介面；先嘗試 Responses，確認不相容後轉 Chat Completions。',
                                                en: 'No endpoint is fixed yet; runtime falls back to Chat Completions when Responses is incompatible.',
                                                fr: 'Aucun endpoint n’est fixé ; Chat Completions prend le relais si Responses est incompatible.',
                                                de: 'Noch kein Endpunkt festgelegt; bei inkompatiblem Responses folgt Chat Completions.',
                                                ja: 'エンドポイントは未確定です。Responses が非互換の場合は Chat Completions に切り替えます。',
                                              )
                                      : openHandLocalizedText(
                                          context,
                                          zh: 'Responses 已禁用，运行时使用 Chat Completions。',
                                          zhHant:
                                              'Responses 已停用，執行時使用 Chat Completions。',
                                          en: 'Responses is disabled; Chat Completions is used at runtime.',
                                          fr: 'Responses est désactivé ; Chat Completions est utilisé.',
                                          de: 'Responses ist deaktiviert; Chat Completions wird verwendet.',
                                          ja: 'Responses は無効です。Chat Completions を使用します。',
                                        )
                                : openHandLocalizedText(
                                    context,
                                    zh: '根据当前协议展示实际请求端点。',
                                    zhHant: '依照目前協定顯示實際請求端點。',
                                    en: 'Shows the effective endpoint for the selected protocol.',
                                    fr: 'Affiche le endpoint effectif du protocole sélectionné.',
                                    de: 'Zeigt den effektiven Endpunkt des gewählten Protokolls.',
                                    ja: '選択したプロトコルの実際のエンドポイントを表示します。',
                                  ),
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (usesResponsesRouting &&
                              preview.responses.isNotEmpty) ...[
                            kOpenHandGap10,
                            _EndpointPreviewRow(
                              icon: Icons.auto_awesome_rounded,
                              label: openHandLocalizedText(
                                context,
                                zh: _responsesCapabilityStatus == 'supported'
                                    ? '已验证 · Responses'
                                    : '首试 · Responses',
                                zhHant:
                                    _responsesCapabilityStatus == 'supported'
                                    ? '已驗證 · Responses'
                                    : '首試 · Responses',
                                en: _responsesCapabilityStatus == 'supported'
                                    ? 'Verified · Responses'
                                    : 'First · Responses',
                                fr: _responsesCapabilityStatus == 'supported'
                                    ? 'Vérifié · Responses'
                                    : 'Premier · Responses',
                                de: _responsesCapabilityStatus == 'supported'
                                    ? 'Verifiziert · Responses'
                                    : 'Zuerst · Responses',
                                ja: _responsesCapabilityStatus == 'supported'
                                    ? '検証済み · Responses'
                                    : '最初 · Responses',
                              ),
                              url: preview.responses,
                              color: colorScheme.primary,
                            ),
                          ],
                          kOpenHandGap8,
                          _EndpointPreviewRow(
                            icon:
                                !usesResponsesRouting ||
                                    preview.responses.isEmpty
                                ? Icons.route_rounded
                                : Icons.swap_horiz_rounded,
                            label: !usesResponsesRouting
                                ? openHandLocalizedText(
                                    context,
                                    zh: '当前 · 协议端点',
                                    zhHant: '目前 · 協定端點',
                                    en: 'Active · Protocol Endpoint',
                                    fr: 'Actif · Endpoint du protocole',
                                    de: 'Aktiv · Protokollendpunkt',
                                    ja: '使用中 · プロトコルエンドポイント',
                                  )
                                : preview.responses.isEmpty
                                ? openHandLocalizedText(
                                    context,
                                    zh: '当前 · Chat Completions',
                                    zhHant: '目前 · Chat Completions',
                                    en: 'Active · Chat Completions',
                                    fr: 'Actif · Chat Completions',
                                    de: 'Aktiv · Chat Completions',
                                    ja: '使用中 · Chat Completions',
                                  )
                                : openHandLocalizedText(
                                    context,
                                    zh: '回退 · Chat Completions',
                                    zhHant: '回退 · Chat Completions',
                                    en: 'Fallback · Chat Completions',
                                    fr: 'Repli · Chat Completions',
                                    de: 'Fallback · Chat Completions',
                                    ja: 'フォールバック · Chat Completions',
                                  ),
                            url: preview.chat,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  bool _defaultExplicitPromptCacheEnabledFor(AiProtocolType protocolType) {
    return protocolType == AiProtocolType.claude;
  }

  void _handleProtocolChanged(AiProtocolType value) {
    final wasClaude = _showsExplicitPromptCacheControl;
    final nextIsClaude = value == AiProtocolType.claude;
    setState(() {
      _protocolType = value;
      _apiDialect = inferAiApiDialect(value);
      _providerKind = inferAiProviderKind(value);
      if (!nextIsClaude) {
        _explicitPromptCacheEnabled = false;
      } else if (!wasClaude) {
        _explicitPromptCacheEnabled = true;
      }
    });
  }

  Widget _buildExplicitPromptCacheControl({
    required bool globalInputCacheEnabled,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final duration = openHandMotionDuration(context, kOpenHandMotion180);
    final child = !_showsExplicitPromptCacheControl
        ? const SizedBox.shrink(key: ValueKey<String>('cacheControlHidden'))
        : Padding(
            key: const ValueKey<String>('cacheControlVisible'),
            padding: const EdgeInsets.only(top: 16),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(0, 8, 0, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          openHandLocalizedText(
                            context,
                            zh: '启用 Claude 显式提示词缓存点',
                            zhHant: '啟用 Claude 顯式提示詞快取點',
                            en: 'Enable Claude Explicit Prompt Cache Points',
                            fr: 'Activer les points de cache Claude explicites',
                            de: 'Explizite Claude-Prompt-Cachepunkte aktivieren',
                            ja: 'Claude 明示的プロンプトキャッシュ点を有効化',
                          ),
                          style: theme.textTheme.titleSmall,
                        ),
                        kOpenHandGap4,
                        Text(
                          globalInputCacheEnabled
                              ? openHandLocalizedText(
                                  context,
                                  zh: '开启后，Claude native 请求会按成本控制设置插入 cache_control 断点。',
                                  zhHant:
                                      '開啟後，Claude native 請求會依成本控制設定插入 cache_control 斷點。',
                                  en: 'When enabled, Claude native requests insert cache_control breakpoints based on cost-control settings.',
                                  fr: 'Activé, les requêtes Claude native insèrent des points cache_control selon le contrôle des coûts.',
                                  de: 'Aktiviert fügen Claude-native Anfragen cache_control-Punkte gemäß Kostensteuerung ein.',
                                  ja: '有効にすると、Claude native リクエストにコスト制御設定に基づく cache_control ブレークポイントを挿入します。',
                                )
                              : openHandLocalizedText(
                                  context,
                                  zh: '全局输入缓存已关闭；此开关会保存偏好，但当前不会生效。',
                                  zhHant: '全域輸入快取已關閉；此開關會保存偏好，但目前不會生效。',
                                  en: 'Global input caching is off; this switch saves the preference but has no effect now.',
                                  fr: 'Le cache global des entrées est désactivé ; ce choix est enregistré mais sans effet pour l’instant.',
                                  de: 'Globales Eingabe-Caching ist aus; diese Option speichert nur die Präferenz.',
                                  ja: 'グローバル入力キャッシュはオフです。このスイッチは設定を保存しますが、現在は効果がありません。',
                                ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  kOpenHandHGap16,
                  Switch(
                    value: _explicitPromptCacheEnabled,
                    onChanged: _isSaving
                        ? null
                        : (value) {
                            setState(() {
                              _explicitPromptCacheEnabled = value;
                            });
                          },
                  ),
                ],
              ),
            ),
          );
    return AnimatedSize(
      duration: duration,
      curve: kOpenHandSwitchInCurve,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: duration,
        switchInCurve: kOpenHandSwitchInCurve,
        switchOutCurve: kOpenHandSwitchOutCurve,
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: SizeTransition(
              sizeFactor: animation,
              axisAlignment: -1,
              child: child,
            ),
          );
        },
        child: child,
      ),
    );
  }

  Widget _buildModelIdDropdown({
    required String label,
    required String helperText,
    required String? selectedModelId,
    required ValueChanged<String?> onChanged,
    bool allowUnset = false,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final modelIds = _visibleModelIds;
    if (modelIds.isEmpty) {
      return InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          helperText: openHandLocalizedText(
            context,
            zh: '请先扫描模型或手动添加模型 ID。',
            en: 'Scan models or add a model ID first.',
          ),
        ),
        child: Text(
          openHandLocalizedText(
            context,
            zh: '暂无可选模型',
            en: 'No models available',
          ),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    final normalizedSelection = selectedModelId?.trim() ?? '';
    final initialValue = allowUnset && normalizedSelection.isEmpty
        ? ''
        : modelIds.contains(normalizedSelection)
        ? normalizedSelection
        : allowUnset
        ? ''
        : modelIds.first;
    return AnimatedDropdownButtonFormField<String>(
      key: ValueKey<String>(
        '$label::$initialValue::${modelIds.join('\u0001')}',
      ),
      initialValue: initialValue,
      isExpanded: true,
      menuMaxHeight: 320,
      decoration: InputDecoration(labelText: label, helperText: helperText),
      items: <DropdownMenuItem<String>>[
        if (allowUnset)
          DropdownMenuItem<String>(
            value: '',
            child: Text(
              openHandLocalizedText(context, zh: '不设置', en: 'Not set'),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ...modelIds.map(
          (id) => DropdownMenuItem<String>(
            value: id,
            child: Text(id, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: _isSaving
          ? null
          : (value) {
              if (!allowUnset && (value == null || value.trim().isEmpty)) {
                return;
              }
              onChanged(value);
            },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    // 这个 1400 行的编辑器只用到全局输入缓存开关这一项，整体订阅会让任意
    // 一条设置变更都把它整棵重建。
    final globalInputCacheEnabled = context.select<SettingsController, bool>(
      (controller) => controller.aiInputCacheEnabled,
    );

    return PopScope(
      canPop: !_isSaving,
      child: buildOpenHandResponsiveDialogShell(
        context: context,
        maxWidth: kOpenHandDialogWidthWide,
        maxHeight: kOpenHandDialogHeightFull,
        safeAreaMinimum: kOpenHandDialogDefaultInsetPadding,
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
                  kOpenHandGap16,
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
                            kOpenHandGap16,
                            TextFormField(
                              controller: _officialWebsiteUrlController,
                              enabled: !_isSaving,
                              keyboardType: TextInputType.url,
                              decoration: InputDecoration(
                                labelText: l10n.aiModelOfficialWebsiteUrl,
                                hintText: l10n.aiModelOfficialWebsiteUrlHint,
                              ),
                              validator: (value) {
                                final rawValue = value?.trim() ?? '';
                                if (rawValue.isEmpty) {
                                  return null;
                                }
                                if (!isValidHttpUrl(rawValue)) {
                                  return l10n.aiModelOfficialWebsiteUrlInvalid;
                                }
                                return null;
                              },
                            ),
                            kOpenHandGap16,
                            TextFormField(
                              controller: _baseUrlController,
                              enabled: !_isSaving,
                              decoration: InputDecoration(
                                labelText: l10n.aiModelBaseUrl,
                              ),
                              onChanged: (_) {
                                setState(() {});
                              },
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
                            kOpenHandGap16,
                            _buildAutoCompleteBaseUrlControl(),
                            kOpenHandGap16,
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final stacked = constraints.maxWidth < 640;
                                final authDropdown =
                                    AnimatedDropdownButtonFormField<
                                      AiAuthScheme
                                    >(
                                      initialValue: _authScheme,
                                      decoration: InputDecoration(
                                        labelText: l10n.aiModelAuthScheme,
                                      ),
                                      items: AiAuthScheme.values
                                          .map(
                                            (item) =>
                                                DropdownMenuItem<AiAuthScheme>(
                                                  value: item,
                                                  child: Text(item.label(l10n)),
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
                                                if (value ==
                                                    AiAuthScheme.none) {
                                                  _tokenController.clear();
                                                }
                                              });
                                            },
                                    );
                                final protocolDropdown =
                                    AnimatedDropdownButtonFormField<
                                      AiProtocolType
                                    >(
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
                                                  child: Text(item.label(l10n)),
                                                ),
                                          )
                                          .toList(growable: false),
                                      onChanged: _isSaving
                                          ? null
                                          : (value) {
                                              if (value == null) {
                                                return;
                                              }
                                              _handleProtocolChanged(value);
                                            },
                                    );
                                if (stacked) {
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      authDropdown,
                                      kOpenHandGap16,
                                      protocolDropdown,
                                    ],
                                  );
                                }
                                return Row(
                                  children: [
                                    Expanded(child: authDropdown),
                                    kOpenHandHGap16,
                                    Expanded(child: protocolDropdown),
                                  ],
                                );
                              },
                            ),
                            _buildExplicitPromptCacheControl(
                              globalInputCacheEnabled: globalInputCacheEnabled,
                            ),
                            OpenHandVerticalRevealSwitcher(
                              duration: kOpenHandMotion180,
                              child: _usesTokenAuth
                                  ? Column(
                                      key: const ValueKey<String>(
                                        'ai-model-token-field',
                                      ),
                                      children: [
                                        kOpenHandGap16,
                                        TextFormField(
                                          controller: _tokenController,
                                          enabled: !_isSaving,
                                          obscureText: _obscureToken,
                                          decoration: InputDecoration(
                                            labelText: l10n.aiModelToken,
                                            suffixIconConstraints:
                                                const BoxConstraints(
                                                  minWidth: 56,
                                                  minHeight: 40,
                                                ),
                                            suffixIcon: Padding(
                                              padding:
                                                  const EdgeInsetsDirectional.only(
                                                    end: 10,
                                                  ),
                                              child: IconButton(
                                                onPressed: _isSaving
                                                    ? null
                                                    : () {
                                                        setState(() {
                                                          _obscureToken =
                                                              !_obscureToken;
                                                        });
                                                      },
                                                style: IconButton.styleFrom(
                                                  backgroundColor:
                                                      Colors.transparent,
                                                  foregroundColor: colorScheme
                                                      .onSurfaceVariant,
                                                  disabledForegroundColor:
                                                      colorScheme
                                                          .onSurfaceVariant
                                                          .withValues(
                                                            alpha: 0.38,
                                                          ),
                                                  minimumSize: const Size(
                                                    36,
                                                    36,
                                                  ),
                                                  maximumSize: const Size(
                                                    36,
                                                    36,
                                                  ),
                                                  padding: EdgeInsets.zero,
                                                  tapTargetSize:
                                                      MaterialTapTargetSize
                                                          .shrinkWrap,
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                ),
                                                icon: Icon(
                                                  _obscureToken
                                                      ? Icons
                                                            .visibility_outlined
                                                      : Icons
                                                            .visibility_off_outlined,
                                                  size: 22,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    )
                                  : const SizedBox.shrink(
                                      key: ValueKey<String>(
                                        'ai-model-token-field-hidden',
                                      ),
                                    ),
                            ),
                            kOpenHandGap20,
                            // ── Model scan section ──
                            Row(
                              children: [
                                Text(
                                  l10n.aiModelAvailableModels,
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                kOpenHandHGap12,
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
                                  kOpenHandHGap8,
                                  Text(
                                    l10n.aiModelScanning,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                ],
                                const Spacer(),
                                if (_visibleModelIds.length > 1)
                                  _AiModelSearchToggleButton(
                                    visible: _modelSearchVisible,
                                    enabled: !_isSaving,
                                    onPressed: _toggleModelSearch,
                                  ),
                              ],
                            ),
                            if (_scanError != null) ...[
                              kOpenHandGap8,
                              Text(
                                _scanError!,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: colorScheme.error),
                              ),
                            ],
                            _AnimatedSettingReveal(
                              visible:
                                  _modelSearchVisible &&
                                  _visibleModelIds.length > 1,
                              child: Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: _AiModelSearchField(
                                  controller: _modelSearchController,
                                  focusNode: _modelSearchFocusNode,
                                  enabled: !_isSaving,
                                  helperText:
                                      _modelSearchController.text.trim().isEmpty
                                      ? null
                                      : openHandLocalizedText(
                                          context,
                                          zh: '找到 ${_filteredVisibleModelIds.length} / ${_visibleModelIds.length} 个模型',
                                          zhHant:
                                              '找到 ${_filteredVisibleModelIds.length} / ${_visibleModelIds.length} 個模型',
                                          en: '${_filteredVisibleModelIds.length} of ${_visibleModelIds.length} models',
                                          fr: '${_filteredVisibleModelIds.length} modèles sur ${_visibleModelIds.length}',
                                          de: '${_filteredVisibleModelIds.length} von ${_visibleModelIds.length} Modellen',
                                          ja: '${_visibleModelIds.length} 件中 ${_filteredVisibleModelIds.length} 件',
                                        ),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                            ),
                            kOpenHandGap12,
                            if (_filteredVisibleModelIds.isNotEmpty)
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxHeight: 200,
                                ),
                                child: RepaintBoundary(
                                  // 拦截内层越界通知，避免外层滚动区域同步抖动。
                                  child: NotificationListener<OverscrollNotification>(
                                    onNotification: (_) => true,
                                    child: OpenHandSafeScrollbar(
                                      controller: _chipScrollController,
                                      child: SingleChildScrollView(
                                        controller: _chipScrollController,
                                        physics: const ClampingScrollPhysics(),
                                        child: Wrap(
                                          spacing: 8,
                                          runSpacing: 6,
                                          children: _filteredVisibleModelIds
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
                            else if (_visibleModelIds.isEmpty)
                              Text(
                                AppLocalizations.of(
                                  context,
                                )!.mdlEdTapScanModelsToDiscoverModels,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                              )
                            else
                              OpenHandInlineEmptyState(
                                message: openHandLocalizedText(
                                  context,
                                  zh: '没有匹配的模型 ID。',
                                  zhHant: '沒有符合的模型 ID。',
                                  en: 'No matching model IDs.',
                                  fr: 'Aucun ID de modèle correspondant.',
                                  de: 'Keine passende Modell-ID.',
                                  ja: '一致するモデル ID はありません。',
                                ),
                                dense: true,
                              ),
                            kOpenHandGap12,
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
                                kOpenHandHGap8,
                                FilledButton.tonal(
                                  onPressed: _isSaving
                                      ? null
                                      : _addManualModelId,
                                  child: Text(l10n.aiModelManualIdAdd),
                                ),
                              ],
                            ),
                            kOpenHandGap16,
                            _buildModelIdDropdown(
                              label: AppLocalizations.of(
                                context,
                              )!.mdlEdActiveModelId,
                              helperText: AppLocalizations.of(
                                context,
                              )!.mdlEdTheModelUsedForConversationsSelect,
                              selectedModelId: _activeModelId,
                              onChanged: (value) => _selectModelId(value ?? ''),
                            ),
                            kOpenHandGap16,
                            _buildModelIdDropdown(
                              label: openHandLocalizedText(
                                context,
                                zh: '默认标题生成模型 ID',
                                en: 'Default Title Model ID',
                              ),
                              helperText: openHandLocalizedText(
                                context,
                                zh: '当前线程模型不适合生成文本标题时，会优先回退到这里选择的同提供商模型。',
                                en: 'When the thread model is not suitable for text titles, title generation falls back to this sibling provider model first.',
                              ),
                              selectedModelId: _defaultTitleModelId,
                              allowUnset: true,
                              onChanged: _selectDefaultTitleModelId,
                            ),
                            kOpenHandGap16,
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
                                if (optionalPositiveIntFromText(trimmed) ==
                                    null) {
                                  return AppLocalizations.of(
                                    context,
                                  )!.mdlEdEnterAWholeNumberGreaterThan;
                                }
                                return null;
                              },
                            ),
                            kOpenHandGap16,
                            // ── Request configuration section ──
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final stacked = constraints.maxWidth < 640;
                                final methodDropdown =
                                    AnimatedDropdownButtonFormField<String>(
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
                                              color:
                                                  colorScheme.onSurfaceVariant,
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
                                      kOpenHandGap16,
                                      streamToggle,
                                    ],
                                  );
                                }
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: methodDropdown),
                                    kOpenHandHGap16,
                                    Expanded(child: streamToggle),
                                  ],
                                );
                              },
                            ),
                            kOpenHandGap16,
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
                                    if (optionalPositiveIntFromText(trimmed) ==
                                        null) {
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
                                    final parsed = optionalDoubleFromText(
                                      trimmed,
                                    );
                                    if (parsed == null ||
                                        parsed < 0 ||
                                        parsed > _maxTemperature) {
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
                                      kOpenHandGap16,
                                      temperatureField,
                                    ],
                                  );
                                }
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: maxTokensField),
                                    kOpenHandHGap16,
                                    Expanded(child: temperatureField),
                                  ],
                                );
                              },
                            ),
                            kOpenHandGap20,
                            Text(
                              openHandLocalizedText(
                                context,
                                zh: '高级接口配置',
                                zhHant: '進階介面設定',
                                en: 'Advanced API Configuration',
                                fr: 'Configuration API avancée',
                                de: 'Erweiterte API-Konfiguration',
                                ja: '高度な API 設定',
                              ),
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            kOpenHandGap12,
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final stacked = constraints.maxWidth < 640;
                                final dialectDropdown =
                                    AnimatedDropdownButtonFormField<
                                      AiApiDialect
                                    >(
                                      initialValue: _apiDialect,
                                      decoration: InputDecoration(
                                        labelText: openHandLocalizedText(
                                          context,
                                          zh: 'API 方言',
                                          zhHant: 'API 方言',
                                          en: 'API Dialect',
                                          fr: 'Dialecte API',
                                          de: 'API-Dialekt',
                                          ja: 'API ダイアレクト',
                                        ),
                                      ),
                                      items: AiApiDialect.values
                                          .map(
                                            (item) =>
                                                DropdownMenuItem<AiApiDialect>(
                                                  value: item,
                                                  child: Text(
                                                    item.storageValue,
                                                  ),
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
                                    AnimatedDropdownButtonFormField<
                                      AiProviderKind
                                    >(
                                      initialValue: _providerKind,
                                      decoration: InputDecoration(
                                        labelText: openHandLocalizedText(
                                          context,
                                          zh: '服务商类型',
                                          zhHant: '服務商類型',
                                          en: 'Provider Type',
                                          fr: 'Type de fournisseur',
                                          de: 'Anbietertyp',
                                          ja: 'プロバイダー種別',
                                        ),
                                      ),
                                      items: AiProviderKind.values
                                          .map(
                                            (item) =>
                                                DropdownMenuItem<
                                                  AiProviderKind
                                                >(
                                                  value: item,
                                                  child: Text(
                                                    item.storageValue,
                                                  ),
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
                                      kOpenHandGap16,
                                      providerKindDropdown,
                                    ],
                                  );
                                }
                                return Row(
                                  children: [
                                    Expanded(child: dialectDropdown),
                                    kOpenHandHGap16,
                                    Expanded(child: providerKindDropdown),
                                  ],
                                );
                              },
                            ),
                            kOpenHandGap16,
                            TextField(
                              controller: _responsesModelIdController,
                              enabled: !_isSaving,
                              decoration: InputDecoration(
                                labelText: openHandLocalizedText(
                                  context,
                                  zh: 'Responses 模型 ID（可选）',
                                  zhHant: 'Responses 模型 ID（選填）',
                                  en: 'Responses Model ID (optional)',
                                  fr: 'ID du modèle Responses (facultatif)',
                                  de: 'Responses-Modell-ID (optional)',
                                  ja: 'Responses モデル ID（任意）',
                                ),
                              ),
                            ),
                            kOpenHandGap12,
                            TextField(
                              controller: _embeddingModelIdController,
                              enabled: !_isSaving,
                              decoration: InputDecoration(
                                labelText: openHandLocalizedText(
                                  context,
                                  zh: 'Embeddings 模型 ID（可选）',
                                  zhHant: 'Embeddings 模型 ID（選填）',
                                  en: 'Embeddings Model ID (optional)',
                                  fr: 'ID du modèle Embeddings (facultatif)',
                                  de: 'Embeddings-Modell-ID (optional)',
                                  ja: 'Embeddings モデル ID（任意）',
                                ),
                              ),
                            ),
                            kOpenHandGap12,
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final stacked = constraints.maxWidth < 640;
                                final moderationField = TextField(
                                  controller: _moderationModelIdController,
                                  enabled: !_isSaving,
                                  decoration: InputDecoration(
                                    labelText: openHandLocalizedText(
                                      context,
                                      zh: 'Moderations 模型 ID（可选）',
                                      zhHant: 'Moderations 模型 ID（選填）',
                                      en: 'Moderations Model ID (optional)',
                                      fr: 'ID du modèle Moderations (facultatif)',
                                      de: 'Moderations-Modell-ID (optional)',
                                      ja: 'Moderations モデル ID（任意）',
                                    ),
                                  ),
                                );
                                final rerankField = TextField(
                                  controller: _rerankModelIdController,
                                  enabled: !_isSaving,
                                  decoration: InputDecoration(
                                    labelText: openHandLocalizedText(
                                      context,
                                      zh: 'Rerank 模型 ID（可选）',
                                      zhHant: 'Rerank 模型 ID（選填）',
                                      en: 'Rerank Model ID (optional)',
                                      fr: 'ID du modèle Rerank (facultatif)',
                                      de: 'Rerank-Modell-ID (optional)',
                                      ja: 'Rerank モデル ID（任意）',
                                    ),
                                  ),
                                );
                                if (stacked) {
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      moderationField,
                                      kOpenHandGap12,
                                      rerankField,
                                    ],
                                  );
                                }
                                return Row(
                                  children: [
                                    Expanded(child: moderationField),
                                    kOpenHandHGap16,
                                    Expanded(child: rerankField),
                                  ],
                                );
                              },
                            ),
                            kOpenHandGap12,
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final stacked = constraints.maxWidth < 640;
                                final imageField = TextField(
                                  controller: _imageModelIdController,
                                  enabled: !_isSaving,
                                  decoration: InputDecoration(
                                    labelText: openHandLocalizedText(
                                      context,
                                      zh: '图像模型 ID（可选）',
                                      zhHant: '影像模型 ID（選填）',
                                      en: 'Image Model ID (optional)',
                                      fr: 'ID du modèle image (facultatif)',
                                      de: 'Bildmodell-ID (optional)',
                                      ja: '画像モデル ID（任意）',
                                    ),
                                  ),
                                );
                                final videoField = TextField(
                                  controller: _videoModelIdController,
                                  enabled: !_isSaving,
                                  decoration: InputDecoration(
                                    labelText: openHandLocalizedText(
                                      context,
                                      zh: '视频模型 ID（可选）',
                                      zhHant: '影片模型 ID（選填）',
                                      en: 'Video Model ID (optional)',
                                      fr: 'ID du modèle vidéo (facultatif)',
                                      de: 'Videomodell-ID (optional)',
                                      ja: '動画モデル ID（任意）',
                                    ),
                                  ),
                                );
                                if (stacked) {
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      imageField,
                                      kOpenHandGap12,
                                      videoField,
                                    ],
                                  );
                                }
                                return Row(
                                  children: [
                                    Expanded(child: imageField),
                                    kOpenHandHGap16,
                                    Expanded(child: videoField),
                                  ],
                                );
                              },
                            ),
                            kOpenHandGap12,
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final stacked = constraints.maxWidth < 640;
                                final speechField = TextField(
                                  controller: _speechModelIdController,
                                  enabled: !_isSaving,
                                  decoration: InputDecoration(
                                    labelText: openHandLocalizedText(
                                      context,
                                      zh: '语音模型 ID（可选）',
                                      zhHant: '語音模型 ID（選填）',
                                      en: 'Speech Model ID (optional)',
                                      fr: 'ID du modèle vocal (facultatif)',
                                      de: 'Sprachmodell-ID (optional)',
                                      ja: '音声モデル ID（任意）',
                                    ),
                                  ),
                                );
                                final voiceField = TextField(
                                  controller: _defaultVoiceController,
                                  enabled: !_isSaving,
                                  decoration: InputDecoration(
                                    labelText: openHandLocalizedText(
                                      context,
                                      zh: '默认 Voice（可选）',
                                      zhHant: '預設 Voice（選填）',
                                      en: 'Default Voice (optional)',
                                      fr: 'Voix par défaut (facultatif)',
                                      de: 'Standard-Voice (optional)',
                                      ja: 'デフォルト Voice（任意）',
                                    ),
                                  ),
                                );
                                if (stacked) {
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      speechField,
                                      kOpenHandGap12,
                                      voiceField,
                                    ],
                                  );
                                }
                                return Row(
                                  children: [
                                    Expanded(child: speechField),
                                    kOpenHandHGap16,
                                    Expanded(child: voiceField),
                                  ],
                                );
                              },
                            ),
                            kOpenHandGap12,
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final stacked = constraints.maxWidth < 640;
                                final transcriptionField = TextField(
                                  controller: _transcriptionModelIdController,
                                  enabled: !_isSaving,
                                  decoration: InputDecoration(
                                    labelText: openHandLocalizedText(
                                      context,
                                      zh: 'Transcription 模型 ID（可选）',
                                      zhHant: 'Transcription 模型 ID（選填）',
                                      en: 'Transcription Model ID (optional)',
                                      fr: 'ID du modèle Transcription (facultatif)',
                                      de: 'Transcription-Modell-ID (optional)',
                                      ja: 'Transcription モデル ID（任意）',
                                    ),
                                  ),
                                );
                                final translationField = TextField(
                                  controller: _translationModelIdController,
                                  enabled: !_isSaving,
                                  decoration: InputDecoration(
                                    labelText: openHandLocalizedText(
                                      context,
                                      zh: 'Translation 模型 ID（可选）',
                                      zhHant: 'Translation 模型 ID（選填）',
                                      en: 'Translation Model ID (optional)',
                                      fr: 'ID du modèle Translation (facultatif)',
                                      de: 'Translation-Modell-ID (optional)',
                                      ja: 'Translation モデル ID（任意）',
                                    ),
                                  ),
                                );
                                if (stacked) {
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      transcriptionField,
                                      kOpenHandGap12,
                                      translationField,
                                    ],
                                  );
                                }
                                return Row(
                                  children: [
                                    Expanded(child: transcriptionField),
                                    kOpenHandHGap16,
                                    Expanded(child: translationField),
                                  ],
                                );
                              },
                            ),
                            kOpenHandGap12,
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final stacked = constraints.maxWidth < 640;
                                final realtimeTransportField = TextField(
                                  controller: _realtimeTransportController,
                                  enabled: !_isSaving,
                                  decoration: InputDecoration(
                                    labelText: openHandLocalizedText(
                                      context,
                                      zh: 'Realtime Transport（可选）',
                                      zhHant: 'Realtime Transport（選填）',
                                      en: 'Realtime Transport (optional)',
                                      fr: 'Transport Realtime (facultatif)',
                                      de: 'Realtime-Transport (optional)',
                                      ja: 'Realtime Transport（任意）',
                                    ),
                                  ),
                                );
                                final realtimeUrlField = TextField(
                                  controller: _realtimeUrlOverrideController,
                                  enabled: !_isSaving,
                                  decoration: InputDecoration(
                                    labelText: openHandLocalizedText(
                                      context,
                                      zh: 'Realtime URL Override（可选）',
                                      zhHant: 'Realtime URL Override（選填）',
                                      en: 'Realtime URL Override (optional)',
                                      fr: 'URL Realtime personnalisée (facultatif)',
                                      de: 'Realtime-URL-Override (optional)',
                                      ja: 'Realtime URL Override（任意）',
                                    ),
                                  ),
                                );
                                final realtimeModelField = TextField(
                                  controller: _realtimeModelIdController,
                                  enabled: !_isSaving,
                                  decoration: InputDecoration(
                                    labelText: openHandLocalizedText(
                                      context,
                                      zh: 'Realtime 模型 ID（可选）',
                                      zhHant: 'Realtime 模型 ID（選填）',
                                      en: 'Realtime Model ID (optional)',
                                      fr: 'ID du modèle Realtime (facultatif)',
                                      de: 'Realtime-Modell-ID (optional)',
                                      ja: 'Realtime モデル ID（任意）',
                                    ),
                                  ),
                                );
                                if (stacked) {
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      realtimeTransportField,
                                      kOpenHandGap12,
                                      realtimeUrlField,
                                      kOpenHandGap12,
                                      realtimeModelField,
                                    ],
                                  );
                                }
                                return Column(
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(child: realtimeTransportField),
                                        kOpenHandHGap16,
                                        Expanded(child: realtimeUrlField),
                                      ],
                                    ),
                                    kOpenHandGap12,
                                    realtimeModelField,
                                  ],
                                );
                              },
                            ),
                            kOpenHandGap12,
                            TextField(
                              controller: _endpointOverridesController,
                              enabled: !_isSaving,
                              minLines: 4,
                              maxLines: 8,
                              decoration: InputDecoration(
                                labelText: openHandLocalizedText(
                                  context,
                                  zh: 'Endpoint Overrides JSON（可选）',
                                  zhHant: 'Endpoint Overrides JSON（選填）',
                                  en: 'Endpoint Overrides JSON (optional)',
                                  fr: 'JSON de surcharge des endpoints (facultatif)',
                                  de: 'Endpoint-Overrides JSON (optional)',
                                  ja: 'Endpoint Overrides JSON（任意）',
                                ),
                                helperText: openHandLocalizedText(
                                  context,
                                  zh: '按 family 自定义 path/url/method/transport/headers/query_defaults。',
                                  zhHant:
                                      '依 family 自訂 path/url/method/transport/headers/query_defaults。',
                                  en: 'Customize path/url/method/transport/headers/query_defaults by family.',
                                  fr: 'Personnalisez path/url/method/transport/headers/query_defaults par family.',
                                  de: 'path/url/method/transport/headers/query_defaults je family anpassen.',
                                  ja: 'family ごとに path/url/method/transport/headers/query_defaults をカスタマイズします。',
                                ),
                              ),
                            ),
                            kOpenHandGap12,
                            TextField(
                              controller: _operationExtrasController,
                              enabled: !_isSaving,
                              minLines: 4,
                              maxLines: 8,
                              decoration: InputDecoration(
                                labelText: openHandLocalizedText(
                                  context,
                                  zh: 'Operation Extras JSON（可选）',
                                  zhHant: 'Operation Extras JSON（選填）',
                                  en: 'Operation Extras JSON (optional)',
                                  fr: 'JSON des extras d’opération (facultatif)',
                                  de: 'Operation-Extras JSON (optional)',
                                  ja: 'Operation Extras JSON（任意）',
                                ),
                                helperText: openHandLocalizedText(
                                  context,
                                  zh: '放置 responses/realtime/视频等操作的 provider-specific 扩展参数。',
                                  zhHant:
                                      '放置 responses/realtime/影片等操作的 provider-specific 擴充參數。',
                                  en: 'Provider-specific extras for responses/realtime/video operations.',
                                  fr: 'Extras propres au fournisseur pour responses/realtime/vidéo.',
                                  de: 'Anbieterspezifische Extras für responses/realtime/video.',
                                  ja: 'responses/realtime/動画などの provider-specific 拡張パラメータです。',
                                ),
                              ),
                            ),
                            kOpenHandGap12,
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final stacked = constraints.maxWidth < 640;
                                final showsResponsesRouting =
                                    _apiDialect == AiApiDialect.openAiCompat;
                                Widget dropdown({
                                  required String label,
                                  required String value,
                                  required ValueChanged<String?> onChanged,
                                  String? helperText,
                                  List<String> values = const <String>[
                                    'supported',
                                    'experimental',
                                    'disabled',
                                  ],
                                }) {
                                  return AnimatedDropdownButtonFormField<
                                    String
                                  >(
                                    initialValue: value,
                                    decoration: InputDecoration(
                                      labelText: label,
                                      helperText: helperText,
                                    ),
                                    items: values
                                        .map(
                                          (item) => DropdownMenuItem<String>(
                                            value: item,
                                            child: Text(item),
                                          ),
                                        )
                                        .toList(growable: false),
                                    onChanged: _isSaving ? null : onChanged,
                                  );
                                }

                                final responsesDropdown = dropdown(
                                  label: openHandLocalizedText(
                                    context,
                                    zh: 'Responses 路由策略',
                                    zhHant: 'Responses 路由策略',
                                    en: 'Responses Routing',
                                    fr: 'Routage Responses',
                                    de: 'Responses-Routing',
                                    ja: 'Responses ルーティング',
                                  ),
                                  value: _responsesCapabilityStatus,
                                  helperText: openHandLocalizedText(
                                    context,
                                    zh: 'auto 自动探测并短期记忆；supported 始终优先；disabled 直接使用回退端点。',
                                    zhHant:
                                        'auto 自動探測並短期記憶；supported 始終優先；disabled 直接使用回退端點。',
                                    en: 'auto probes and briefly remembers; supported always prefers it; disabled uses fallback directly.',
                                    fr: 'auto détecte et mémorise brièvement ; supported le privilégie toujours ; disabled utilise directement le repli.',
                                    de: 'auto prüft und merkt kurz; supported bevorzugt es immer; disabled nutzt direkt den Fallback.',
                                    ja: 'auto は検出結果を一時保持し、supported は常に優先、disabled は直接フォールバックします。',
                                  ),
                                  values: const <String>[
                                    'auto',
                                    'supported',
                                    'disabled',
                                  ],
                                  onChanged: (value) {
                                    if (value == null) return;
                                    setState(() {
                                      _responsesCapabilityStatus = value;
                                    });
                                  },
                                );
                                final realtimeDropdown = dropdown(
                                  label: openHandLocalizedText(
                                    context,
                                    zh: 'Realtime 能力状态',
                                    zhHant: 'Realtime 能力狀態',
                                    en: 'Realtime Capability',
                                    fr: 'Capacité Realtime',
                                    de: 'Realtime-Fähigkeit',
                                    ja: 'Realtime 機能状態',
                                  ),
                                  value: _realtimeCapabilityStatus,
                                  onChanged: (value) {
                                    if (value == null) return;
                                    setState(() {
                                      _realtimeCapabilityStatus = value;
                                    });
                                  },
                                );
                                final filesDropdown = dropdown(
                                  label: openHandLocalizedText(
                                    context,
                                    zh: 'Files 能力状态',
                                    zhHant: 'Files 能力狀態',
                                    en: 'Files Capability',
                                    fr: 'Capacité fichiers',
                                    de: 'Files-Fähigkeit',
                                    ja: 'Files 機能状態',
                                  ),
                                  value: _filesCapabilityStatus,
                                  onChanged: (value) {
                                    if (value == null) return;
                                    setState(() {
                                      _filesCapabilityStatus = value;
                                    });
                                  },
                                );
                                final fineTunesDropdown = dropdown(
                                  label: openHandLocalizedText(
                                    context,
                                    zh: 'Fine-tunes 能力状态',
                                    zhHant: 'Fine-tunes 能力狀態',
                                    en: 'Fine-tunes Capability',
                                    fr: 'Capacité fine-tunes',
                                    de: 'Fine-tunes-Fähigkeit',
                                    ja: 'Fine-tunes 機能状態',
                                  ),
                                  value: _fineTunesCapabilityStatus,
                                  onChanged: (value) {
                                    if (value == null) return;
                                    setState(() {
                                      _fineTunesCapabilityStatus = value;
                                    });
                                  },
                                );
                                if (stacked) {
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (showsResponsesRouting) ...[
                                        responsesDropdown,
                                        kOpenHandGap12,
                                      ],
                                      realtimeDropdown,
                                      kOpenHandGap12,
                                      filesDropdown,
                                      kOpenHandGap12,
                                      fineTunesDropdown,
                                    ],
                                  );
                                }
                                if (!showsResponsesRouting) {
                                  return Column(
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(child: realtimeDropdown),
                                          kOpenHandHGap16,
                                          Expanded(child: filesDropdown),
                                        ],
                                      ),
                                      kOpenHandGap12,
                                      fineTunesDropdown,
                                    ],
                                  );
                                }
                                return Column(
                                  children: [
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(child: responsesDropdown),
                                        kOpenHandHGap16,
                                        Expanded(child: realtimeDropdown),
                                      ],
                                    ),
                                    kOpenHandGap12,
                                    Row(
                                      children: [
                                        Expanded(child: filesDropdown),
                                        kOpenHandHGap16,
                                        Expanded(child: fineTunesDropdown),
                                      ],
                                    ),
                                  ],
                                );
                              },
                            ),
                            kOpenHandGap20,
                            // ── Custom headers section ──
                            Row(
                              children: [
                                Text(
                                  AppLocalizations.of(
                                    context,
                                  )!.mdlEdCustomHeaders,
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                const Spacer(),
                                FilledButton.tonalIcon(
                                  onPressed: _isSaving ? null : _addHeaderEntry,
                                  icon: const Icon(Icons.add, size: 18),
                                  label: Text(
                                    AppLocalizations.of(context)!.mdlEdAdd,
                                  ),
                                ),
                              ],
                            ),
                            kOpenHandGap8,
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
                                      kOpenHandHGap8,
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
                                      kOpenHandHGap4,
                                      IconButton(
                                        onPressed: _isSaving
                                            ? null
                                            : () => _removeHeaderEntry(index),
                                        icon: const Icon(Icons.close, size: 18),
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
                            OpenHandDialogErrorText(
                              message: _errorMessage,
                              topGap: 16,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  OpenHandDialogSaveActions(
                    busy: _isSaving,
                    cancelLabel: l10n.commonCancel,
                    confirmLabel: l10n.commonSave,
                    onConfirm: _handleSave,
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

    final Map<String, Object?> endpointOverridesJson;
    final Map<String, Object?> operationExtrasJson;
    try {
      endpointOverridesJson = _decodeJsonObject(
        _endpointOverridesController.text,
      );
      operationExtrasJson = _decodeJsonObject(_operationExtrasController.text);
    } on FormatException catch (error) {
      setState(() {
        _isSaving = false;
        _errorMessage = error.message;
      });
      _errorPulse.value++;
      return;
    }

    final model = AiModelConfig(
      id:
          widget.initialModel?.id ??
          context.read<SettingsController>().createAiModelId(),
      name: _nameController.text.trim(),
      officialWebsiteUrl: _officialWebsiteUrlController.text.trim(),
      baseUrl: _baseUrlController.text.trim(),
      autoCompleteBaseUrl: _autoCompleteBaseUrl,
      authScheme: _authScheme,
      token: _effectiveToken,
      modelId: _modelIdController.text.trim(),
      protocolType: _protocolType,
      apiDialect: _apiDialect,
      providerKind: _providerKind,
      explicitPromptCacheEnabled:
          _showsExplicitPromptCacheControl && _explicitPromptCacheEnabled,
      maxContextTokens: optionalPositiveIntFromText(
        _maxContextTokensController.text,
      ),
      availableModelIds: _availableModelIds,
      defaultTitleModelId: _defaultTitleModelId?.trim() ?? '',
      customHeaders: _collectCustomHeaders(),
      requestMethod: _requestMethod,
      maxTokens: optionalPositiveIntFromText(_maxTokensController.text),
      temperature: optionalDoubleFromText(_temperatureController.text),
      streamEnabled: _streamEnabled,
      modelProfiles: _modelProfiles,
      operationRouting: AiOperationRouting(
        responsesModelId: nullIfBlank(_responsesModelIdController.text),
        embeddingModelId: nullIfBlank(_embeddingModelIdController.text),
        moderationModelId: nullIfBlank(_moderationModelIdController.text),
        rerankModelId: nullIfBlank(_rerankModelIdController.text),
        imageModelId: nullIfBlank(_imageModelIdController.text),
        videoModelId: nullIfBlank(_videoModelIdController.text),
        speechModelId: nullIfBlank(_speechModelIdController.text),
        transcriptionModelId: nullIfBlank(_transcriptionModelIdController.text),
        translationModelId: nullIfBlank(_translationModelIdController.text),
        realtimeModelId: nullIfBlank(_realtimeModelIdController.text),
        defaultVoice: nullIfBlank(_defaultVoiceController.text),
      ),
      endpointOverrides: parseAiEndpointOverrides(endpointOverridesJson),
      capabilityOverrides: <AiApiFamily, String>{
        if (_apiDialect == AiApiDialect.openAiCompat)
          AiApiFamily.responses: _responsesCapabilityStatus,
        AiApiFamily.realtime: _realtimeCapabilityStatus,
        AiApiFamily.files: _filesCapabilityStatus,
        AiApiFamily.fineTunes: _fineTunesCapabilityStatus,
      },
      operationExtras: operationExtrasJson,
      realtime: AiRealtimeConfig(
        transport: nullIfBlank(_realtimeTransportController.text),
        urlOverride: nullIfBlank(_realtimeUrlOverrideController.text),
      ),
    );

    final settingsController = context.read<SettingsController>();
    if (settingsController.isAiModelProviderEndpointBlocked(model.baseUrl)) {
      setState(() {
        _isSaving = false;
        _errorMessage = _aiModelProxyEndpointBlockedMessage(context);
      });
      _errorPulse.value++;
      return;
    }

    late final bool saved;
    try {
      saved = await settingsController.saveAiModel(model);
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

  Map<String, Object?> _decodeJsonObject(String rawValue) {
    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) {
      return const <String, Object?>{};
    }
    return optionalStringKeyedMapFromJsonText(trimmed) ??
        (throw const FormatException('高级 JSON 配置必须是合法的 JSON 对象。'));
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

class _ModelProfileEditorResult {
  const _ModelProfileEditorResult({
    required this.modelId,
    required this.profile,
  });

  final String modelId;
  final AiModelProfile profile;
}

class _OneMillionContextSnapshot {
  const _OneMillionContextSnapshot({
    required this.modelId,
    required this.maxContextLength,
  });

  final String modelId;
  final String maxContextLength;
}

typedef _DuplicateModelProfileCallback =
    String Function(String sourceModelId, AiModelProfile profile);

class _ModelProfileEditorDialog extends StatefulWidget {
  const _ModelProfileEditorDialog({
    required this.modelId,
    required this.existingModelIds,
    required this.initialProfile,
    required this.effectiveProfile,
    required this.protocolType,
    required this.onDuplicate,
    this.showDuplicateAction = true,
  });

  final String modelId;
  final List<String> existingModelIds;
  final AiModelProfile initialProfile;
  final AiModelProfile effectiveProfile;
  final AiProtocolType protocolType;
  final _DuplicateModelProfileCallback onDuplicate;
  final bool showDuplicateAction;

  @override
  State<_ModelProfileEditorDialog> createState() =>
      _ModelProfileEditorDialogState();
}

class _ModelProfileEditorDialogState extends State<_ModelProfileEditorDialog> {
  static const double _reasoningEffortListMinHeight = 240;
  static const double _reasoningEffortListMaxHeight = 440;
  static const double _reasoningEffortCollapsedCardExtent = 86;

  late final TextEditingController _modelIdController;
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
  late final TextEditingController _supportedParametersController;
  late final TextEditingController _defaultParametersController;
  late final TextEditingController _embeddingDimensionsController;
  late final TextEditingController _embeddingMaxInputTokensController;
  late final TextEditingController _embeddingEndpointPathController;
  late final TextEditingController _embeddingBatchSizeController;
  late final TextEditingController _embeddingQueryModelIdController;
  late final TextEditingController _embeddingDocumentModelIdController;
  late final TextEditingController _embeddingInputTypesController;
  late final TextEditingController _embeddingDefaultInputTypeController;
  late final TextEditingController _embeddingQueryInputTypeController;
  late final TextEditingController _embeddingDocumentInputTypeController;
  late final TextEditingController _embeddingSupportedTaskTypesController;
  late final TextEditingController _embeddingDefaultTaskTypeController;
  late final TextEditingController _embeddingDefaultQueryTaskTypeController;
  late final TextEditingController _embeddingDefaultDocumentTaskTypeController;
  late final TextEditingController _embeddingQueryTextPrefixController;
  late final TextEditingController _embeddingDocumentTextPrefixController;
  late final TextEditingController _embeddingEncodingFormatsController;
  late final TextEditingController _embeddingDefaultEncodingFormatController;
  late final TextEditingController _embeddingOutputDTypesController;
  late final TextEditingController _embeddingDefaultOutputDTypeController;
  late final TextEditingController _embeddingDefaultTruncationController;
  late final TextEditingController _embeddingSimilarityMetricController;
  late final TextEditingController _embeddingMinDimensionsController;
  late final TextEditingController _embeddingMaxDimensionsController;
  late final TextEditingController _embeddingMaxInputsPerBatchController;
  late final TextEditingController _embeddingMaxTokensPerBatchController;
  late Set<String> _readerSourceTypes;
  late Set<String> _readerTargetTypes;
  bool? _isMultimodal;
  bool? _supportsAttachments;
  bool? _requiresReasoningEcho;
  late bool _thinkingEnabled;
  late bool _reasoningEffortControlEnabled;
  String? _reasoningEffort;
  late final List<_ReasoningEffortOptionDraft> _reasoningEffortOptionDrafts;
  late final ScrollController _reasoningEffortOptionsScrollController;
  bool _oneMillionContextEnabled = false;
  _OneMillionContextSnapshot? _oneMillionContextSnapshot;
  bool? _embeddingOutputsNormalized;
  bool _embeddingSupportsCustomDimensions = false;
  bool _embeddingRequiresSpecialBody = false;
  bool _embeddingSupportsTruncation = false;
  late bool _isGlobalDefaultTitleModel;
  late Set<AiModelModality> _supportedModalities;
  late Set<AiModelCapability> _capabilities;
  late final Set<String> _reservedModelIds;
  String? _profileErrorMessage;

  @override
  void initState() {
    super.initState();
    final p = widget.initialProfile;
    final effective = widget.effectiveProfile;
    final hasExisting = p.hasUserOverrides;
    _isGlobalDefaultTitleModel = p.isGlobalDefaultTitleModel;
    _modelIdController = TextEditingController(text: widget.modelId);
    _reservedModelIds = widget.existingModelIds.toSet();

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
    _thinkingEnabled =
        p.thinkingEnabled ??
        AiModelConfig.thinkingEnabledByDefault(
          modelId: widget.modelId,
          protocolType: widget.protocolType,
          profile: effective,
        );
    _reasoningEffortControlEnabled =
        _thinkingEnabled &&
        (p.reasoningEffortControlEnabled ??
            effective.reasoningEffortControlEnabled ??
            false);
    _reasoningEffort = p.reasoningEffort ?? effective.reasoningEffort;
    final reasoningOptions = p.reasoningEffortOptions.isNotEmpty
        ? p.reasoningEffortOptions
        : effective.reasoningEffortOptions;
    _reasoningEffortOptionDrafts = reasoningOptions
        .where((option) => option.isValid)
        .map(_ReasoningEffortOptionDraft.fromOption)
        .toList();
    _reasoningEffortOptionsScrollController = ScrollController();
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
    _supportedParametersController = TextEditingController(
      text: _joinCsv(
        p.supportedParameters.isNotEmpty
            ? p.supportedParameters
            : effective.supportedParameters,
      ),
    );
    _defaultParametersController = TextEditingController(
      text: prettyPrintJson(
        p.defaultParameters.isNotEmpty
            ? p.defaultParameters
            : effective.defaultParameters,
        emptyMapAsBlank: true,
      ),
    );
    _embeddingDimensionsController = TextEditingController(
      text:
          p.embeddingDimensions?.toString() ??
          effective.embeddingDimensions?.toString() ??
          '',
    );
    _embeddingMaxInputTokensController = TextEditingController(
      text:
          p.embeddingMaxInputTokens?.toString() ??
          effective.embeddingMaxInputTokens?.toString() ??
          '',
    );
    _embeddingEndpointPathController = TextEditingController(
      text: p.embeddingEndpointPath ?? effective.embeddingEndpointPath ?? '',
    );
    _embeddingBatchSizeController = TextEditingController(
      text:
          p.embeddingBatchSize?.toString() ??
          effective.embeddingBatchSize?.toString() ??
          '',
    );
    _embeddingQueryModelIdController = TextEditingController(
      text: p.embeddingQueryModelId ?? effective.embeddingQueryModelId ?? '',
    );
    _embeddingDocumentModelIdController = TextEditingController(
      text:
          p.embeddingDocumentModelId ??
          effective.embeddingDocumentModelId ??
          '',
    );
    _embeddingInputTypesController = TextEditingController(
      text: _joinCsv(
        p.embeddingInputTypes.isNotEmpty
            ? p.embeddingInputTypes
            : effective.embeddingInputTypes,
      ),
    );
    _embeddingDefaultInputTypeController = TextEditingController(
      text:
          p.embeddingDefaultInputType ??
          effective.embeddingDefaultInputType ??
          '',
    );
    _embeddingQueryInputTypeController = TextEditingController(
      text:
          p.embeddingQueryInputType ?? effective.embeddingQueryInputType ?? '',
    );
    _embeddingDocumentInputTypeController = TextEditingController(
      text:
          p.embeddingDocumentInputType ??
          effective.embeddingDocumentInputType ??
          '',
    );
    _embeddingSupportedTaskTypesController = TextEditingController(
      text: _joinCsv(
        p.embeddingSupportedTaskTypes.isNotEmpty
            ? p.embeddingSupportedTaskTypes
            : effective.embeddingSupportedTaskTypes,
      ),
    );
    _embeddingDefaultTaskTypeController = TextEditingController(
      text:
          p.embeddingDefaultTaskType ??
          effective.embeddingDefaultTaskType ??
          '',
    );
    _embeddingDefaultQueryTaskTypeController = TextEditingController(
      text:
          p.embeddingDefaultQueryTaskType ??
          effective.embeddingDefaultQueryTaskType ??
          '',
    );
    _embeddingDefaultDocumentTaskTypeController = TextEditingController(
      text:
          p.embeddingDefaultDocumentTaskType ??
          effective.embeddingDefaultDocumentTaskType ??
          '',
    );
    _embeddingQueryTextPrefixController = TextEditingController(
      text:
          p.embeddingQueryTextPrefix ??
          effective.embeddingQueryTextPrefix ??
          '',
    );
    _embeddingDocumentTextPrefixController = TextEditingController(
      text:
          p.embeddingDocumentTextPrefix ??
          effective.embeddingDocumentTextPrefix ??
          '',
    );
    _embeddingEncodingFormatsController = TextEditingController(
      text: _joinCsv(
        p.embeddingEncodingFormats.isNotEmpty
            ? p.embeddingEncodingFormats
            : effective.embeddingEncodingFormats,
      ),
    );
    _embeddingDefaultEncodingFormatController = TextEditingController(
      text:
          p.embeddingDefaultEncodingFormat ??
          effective.embeddingDefaultEncodingFormat ??
          '',
    );
    _embeddingOutputDTypesController = TextEditingController(
      text: _joinCsv(
        p.embeddingOutputDTypes.isNotEmpty
            ? p.embeddingOutputDTypes
            : effective.embeddingOutputDTypes,
      ),
    );
    _embeddingDefaultOutputDTypeController = TextEditingController(
      text:
          p.embeddingDefaultOutputDType ??
          effective.embeddingDefaultOutputDType ??
          '',
    );
    _embeddingDefaultTruncationController = TextEditingController(
      text:
          p.embeddingDefaultTruncation ??
          effective.embeddingDefaultTruncation ??
          '',
    );
    _embeddingSimilarityMetricController = TextEditingController(
      text:
          p.embeddingSimilarityMetric ??
          effective.embeddingSimilarityMetric ??
          '',
    );
    _embeddingMinDimensionsController = TextEditingController(
      text:
          p.embeddingMinDimensions?.toString() ??
          effective.embeddingMinDimensions?.toString() ??
          '',
    );
    _embeddingMaxDimensionsController = TextEditingController(
      text:
          p.embeddingMaxDimensions?.toString() ??
          effective.embeddingMaxDimensions?.toString() ??
          '',
    );
    _embeddingMaxInputsPerBatchController = TextEditingController(
      text:
          p.embeddingMaxInputsPerBatch?.toString() ??
          effective.embeddingMaxInputsPerBatch?.toString() ??
          '',
    );
    _embeddingMaxTokensPerBatchController = TextEditingController(
      text:
          p.embeddingMaxTokensPerBatch?.toString() ??
          effective.embeddingMaxTokensPerBatch?.toString() ??
          '',
    );
    _embeddingOutputsNormalized =
        p.embeddingOutputsNormalized ?? effective.embeddingOutputsNormalized;
    _embeddingSupportsCustomDimensions =
        p.embeddingSupportsCustomDimensions ||
        effective.embeddingSupportsCustomDimensions;
    _embeddingRequiresSpecialBody =
        p.embeddingRequiresSpecialBody ||
        effective.embeddingRequiresSpecialBody;
    _embeddingSupportsTruncation =
        p.embeddingSupportsTruncation || effective.embeddingSupportsTruncation;
    _readerSourceTypes = ReaderFileType.normalizeList(
      p.readerSourceTypes.isNotEmpty
          ? p.readerSourceTypes
          : effective.readerSourceTypes,
    ).toSet();
    _readerTargetTypes = ReaderFileType.normalizeList(
      p.readerTargetTypes.isNotEmpty
          ? p.readerTargetTypes
          : effective.readerTargetTypes,
    ).toSet();

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
    if (_capabilities.contains(AiModelCapability.readerConversion)) {
      _ensureDefaultReaderTypes();
    }
    _initializeOneMillionContextState();
  }

  /// 根据协议和模型标识推断输入模态。
  Set<AiModelModality> _inferModalities() {
    final result = <AiModelModality>{AiModelModality.text};
    // 构造最小配置，通过适配器注册表判断图片输入能力。
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

  /// 根据协议规则推断生成能力。
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
    final normalizedModelId = widget.modelId.toLowerCase();
    if (normalizedModelId.contains('rerank') ||
        normalizedModelId.contains('reranker')) {
      result.add(AiModelCapability.rerank);
    }
    if (normalizedModelId.contains('reader') ||
        normalizedModelId.contains('readerlm') ||
        normalizedModelId.contains('docling') ||
        normalizedModelId.contains('marker') ||
        normalizedModelId.contains('html2markdown')) {
      result.add(AiModelCapability.readerConversion);
    }
    return result;
  }

  @override
  void dispose() {
    _modelIdController.dispose();
    _displayNameController.dispose();
    _descriptionController.dispose();
    _maxContextLengthController.dispose();
    _maxSummaryLengthController.dispose();
    _maxOutputLengthController.dispose();
    _maxThinkingLengthController.dispose();
    for (final draft in _reasoningEffortOptionDrafts) {
      draft.dispose();
    }
    _reasoningEffortOptionsScrollController.dispose();
    _inputUsdPer1MController.dispose();
    _outputUsdPer1MController.dispose();
    _cacheReadUsdPer1MController.dispose();
    _cacheWriteUsdPer1MController.dispose();
    _canonicalSlugController.dispose();
    _huggingFaceIdController.dispose();
    _knowledgeCutoffController.dispose();
    _expirationDateController.dispose();
    _supportedParametersController.dispose();
    _defaultParametersController.dispose();
    _embeddingDimensionsController.dispose();
    _embeddingMaxInputTokensController.dispose();
    _embeddingEndpointPathController.dispose();
    _embeddingBatchSizeController.dispose();
    _embeddingQueryModelIdController.dispose();
    _embeddingDocumentModelIdController.dispose();
    _embeddingInputTypesController.dispose();
    _embeddingDefaultInputTypeController.dispose();
    _embeddingQueryInputTypeController.dispose();
    _embeddingDocumentInputTypeController.dispose();
    _embeddingSupportedTaskTypesController.dispose();
    _embeddingDefaultTaskTypeController.dispose();
    _embeddingDefaultQueryTaskTypeController.dispose();
    _embeddingDefaultDocumentTaskTypeController.dispose();
    _embeddingQueryTextPrefixController.dispose();
    _embeddingDocumentTextPrefixController.dispose();
    _embeddingEncodingFormatsController.dispose();
    _embeddingDefaultEncodingFormatController.dispose();
    _embeddingOutputDTypesController.dispose();
    _embeddingDefaultOutputDTypeController.dispose();
    _embeddingDefaultTruncationController.dispose();
    _embeddingSimilarityMetricController.dispose();
    _embeddingMinDimensionsController.dispose();
    _embeddingMaxDimensionsController.dispose();
    _embeddingMaxInputsPerBatchController.dispose();
    _embeddingMaxTokensPerBatchController.dispose();
    super.dispose();
  }

  static String _joinCsv(List<String> values) => values.join(', ');

  List<String> _parseCsv(String value) {
    final seen = <String>{};
    final result = <String>[];
    for (final item in splitTrimmedNonEmpty(value)) {
      if (!seen.add(item)) continue;
      result.add(item);
    }
    return result;
  }

  _ReasoningEffortOptionsSnapshot _reasoningEffortOptionsSnapshot() {
    final result = <AiReasoningEffortOption>[];
    final seen = <String>{};
    for (final draft in _reasoningEffortOptionDrafts) {
      if (!draft.hasAnyText) continue;
      final option = draft.toOption();
      if (option == null) {
        return _ReasoningEffortOptionsSnapshot(
          options: result,
          hasIncompleteRow: true,
        );
      }
      if (!seen.add(option.value)) {
        return _ReasoningEffortOptionsSnapshot(
          options: result,
          duplicateValue: option.value,
        );
      }
      result.add(option);
    }
    return _ReasoningEffortOptionsSnapshot(options: result);
  }

  List<AiReasoningEffortOption> _currentReasoningEffortOptions() {
    return _reasoningEffortOptionsSnapshot().options
        .where((option) => option.isSelectable)
        .toList(growable: false);
  }

  void _syncReasoningEffortSelection({List<AiReasoningEffortOption>? options}) {
    final availableOptions = options ?? _currentReasoningEffortOptions();
    final values = availableOptions.map((item) => item.value).toSet();
    final current = nullIfBlank(_reasoningEffort);
    if (current != null && values.contains(current)) return;
    _reasoningEffort = availableOptions.isEmpty
        ? null
        : availableOptions.first.value;
  }

  void _ensureReasoningEffortDraft() {
    if (_reasoningEffortOptionDrafts.isNotEmpty) return;
    _reasoningEffortOptionDrafts.add(_ReasoningEffortOptionDraft.empty());
  }

  void _addReasoningEffortOptionDraft() {
    setState(() {
      _reasoningEffortOptionDrafts.add(_ReasoningEffortOptionDraft.empty());
      _syncReasoningEffortSelection();
    });
  }

  void _applyReasoningEffortPreset(AiReasoningEffortPreset preset) {
    for (final draft in _reasoningEffortOptionDrafts) {
      draft.dispose();
    }
    setState(() {
      _reasoningEffortOptionDrafts
        ..clear()
        ..addAll(preset.options.map(_ReasoningEffortOptionDraft.fromOption));
      _reasoningEffort = preset.defaultValue;
      _syncReasoningEffortSelection();
    });
    showOpenHandSuccessSnack(
      context,
      openHandLocalizedText(
        context,
        zh: '已应用 ${preset.label} 推理档位模板',
        zhHant: '已套用 ${preset.label} 推理檔位範本',
        en: '${preset.label} reasoning preset applied',
        fr: 'Préréglage de raisonnement ${preset.label} appliqué',
        de: '${preset.label}-Denkvoreinstellung angewendet',
        ja: '${preset.label} 推論プリセットを適用しました',
      ),
      duration: kOpenHandMotion1800,
    );
  }

  void _removeReasoningEffortOptionDraft(_ReasoningEffortOptionDraft draft) {
    setState(() {
      _reasoningEffortOptionDrafts.remove(draft);
      draft.dispose();
      _syncReasoningEffortSelection();
    });
  }

  void _reorderReasoningEffortOptionDrafts(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _reasoningEffortOptionDrafts.length) {
      return;
    }
    setState(() {
      final adjustedNewIndex = newIndex > oldIndex ? newIndex - 1 : newIndex;
      final targetIndex = adjustedNewIndex.clamp(
        0,
        _reasoningEffortOptionDrafts.length - 1,
      );
      final draft = _reasoningEffortOptionDrafts.removeAt(oldIndex);
      _reasoningEffortOptionDrafts.insert(targetIndex, draft);
      _syncReasoningEffortSelection();
    });
  }

  void _setReasoningEffortOptionEnabled(
    _ReasoningEffortOptionDraft draft,
    bool value,
  ) {
    setState(() {
      draft.enabled = value;
      if (!value && draft.expanded) {
        draft.expanded = false;
      }
      _syncReasoningEffortSelection();
    });
  }

  void _toggleReasoningEffortOptionExpanded(_ReasoningEffortOptionDraft draft) {
    setState(() => draft.expanded = !draft.expanded);
  }

  double _reasoningEffortOptionsListHeight() {
    if (_reasoningEffortOptionDrafts.isEmpty) {
      return _reasoningEffortListMinHeight;
    }
    final estimated =
        _reasoningEffortOptionDrafts.length *
            _reasoningEffortCollapsedCardExtent +
        20;
    return estimated
        .clamp(_reasoningEffortListMinHeight, _reasoningEffortListMaxHeight)
        .toDouble();
  }

  void _ensureDefaultReaderTypes() {
    if (_readerSourceTypes.isEmpty) {
      _readerSourceTypes = ReaderFileType.normalizeList(
        ReaderFileType.sourceTypes,
      ).toSet();
    }
    if (_readerTargetTypes.isEmpty) {
      _readerTargetTypes = <String>{ReaderFileType.markdown};
    }
  }

  Map<String, Object?> _parseJsonObject(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return const <String, Object?>{};
    return optionalStringKeyedMapFromJsonText(trimmed) ??
        (throw const FormatException('JSON value must be an object.'));
  }

  String? _validatedModelId() {
    if (_oneMillionContextEnabled) {
      _syncOneMillionContextFields();
    }
    final modelId = _modelIdController.text.trim();
    if (modelId.isEmpty) {
      setState(() {
        _profileErrorMessage = openHandLocalizedText(
          context,
          zh: '模型 ID 不能为空。',
          zhHant: '模型 ID 不能為空。',
          en: 'Model ID cannot be empty.',
          fr: 'L’ID du modèle ne peut pas être vide.',
          de: 'Die Modell-ID darf nicht leer sein.',
          ja: 'モデル ID は空にできません。',
        );
      });
      return null;
    }
    final conflicts =
        _reservedModelIds.contains(modelId) && modelId != widget.modelId;
    if (conflicts) {
      setState(() {
        _profileErrorMessage = openHandLocalizedText(
          context,
          zh: '模型 ID 已存在，请换一个唯一 ID。',
          zhHant: '模型 ID 已存在，請換一個唯一 ID。',
          en: 'Model ID already exists. Use a unique ID.',
          fr: 'Cet ID de modèle existe déjà. Utilisez un ID unique.',
          de: 'Diese Modell-ID existiert bereits. Nutze eine eindeutige ID.',
          ja: 'モデル ID は既に存在します。一意の ID を使用してください。',
        );
      });
      return null;
    }
    return modelId;
  }

  AiModelProfile? _collectProfile() {
    late final Map<String, Object?> defaultParameters;
    try {
      defaultParameters = _parseJsonObject(_defaultParametersController.text);
    } on FormatException {
      setState(() {
        _profileErrorMessage = openHandLocalizedText(
          context,
          zh: 'default_parameters 必须是合法的 JSON 对象。',
          zhHant: 'default_parameters 必須是合法的 JSON 物件。',
          en: 'default_parameters must be a valid JSON object.',
          fr: 'default_parameters doit être un objet JSON valide.',
          de: 'default_parameters muss ein gültiges JSON-Objekt sein.',
          ja: 'default_parameters は有効な JSON オブジェクトである必要があります。',
        );
      });
      return null;
    }
    if (_profileErrorMessage != null) {
      setState(() => _profileErrorMessage = null);
    }
    final reasoningEffortOptionsSnapshot = _reasoningEffortOptionsSnapshot();
    final reasoningEffortOptions = reasoningEffortOptionsSnapshot.options;
    final selectableReasoningEffortOptions = reasoningEffortOptions
        .where((option) => option.isSelectable)
        .toList(growable: false);
    final reasoningEffortControlEnabled =
        _thinkingEnabled && _reasoningEffortControlEnabled;
    if (reasoningEffortOptionsSnapshot.hasIncompleteRow) {
      setState(() {
        _profileErrorMessage = openHandLocalizedText(
          context,
          zh: '推理强度档位的原生值不能为空。',
          zhHant: '推理強度檔位的原生值不能為空。',
          en: 'Reasoning effort options need a native value.',
          fr: 'Chaque option d’effort doit avoir une valeur native.',
          de: 'Reasoning-Effort-Optionen benötigen einen nativen Wert.',
          ja: '推論強度オプションにはネイティブ値が必要です。',
        );
      });
      return null;
    }
    final duplicateReasoningEffort =
        reasoningEffortOptionsSnapshot.duplicateValue;
    if (duplicateReasoningEffort != null) {
      setState(() {
        _profileErrorMessage = openHandLocalizedText(
          context,
          zh: '推理强度原生值不能重复：$duplicateReasoningEffort',
          zhHant: '推理強度原生值不能重複：$duplicateReasoningEffort',
          en: 'Reasoning effort native values must be unique: $duplicateReasoningEffort',
          fr: 'Les valeurs natives d’effort doivent être uniques : $duplicateReasoningEffort',
          de: 'Native Reasoning-Effort-Werte müssen eindeutig sein: $duplicateReasoningEffort',
          ja: '推論強度のネイティブ値は重複できません: $duplicateReasoningEffort',
        );
      });
      return null;
    }
    String? normalizedReasoningEffort = nullIfBlank(_reasoningEffort);
    if (normalizedReasoningEffort != null &&
        !selectableReasoningEffortOptions.any(
          (option) => option.value == normalizedReasoningEffort,
        )) {
      normalizedReasoningEffort = null;
    }
    if (normalizedReasoningEffort == null) {
      for (final option in selectableReasoningEffortOptions) {
        if (option.isSelectable) {
          normalizedReasoningEffort = option.value;
          break;
        }
      }
    }
    if (reasoningEffortControlEnabled && normalizedReasoningEffort == null) {
      setState(() {
        _profileErrorMessage = openHandLocalizedText(
          context,
          zh: '启用推理强度控制时至少需要一个已启用的有效档位。',
          zhHant: '啟用推理強度控制時至少需要一個已啟用的有效檔位。',
          en: 'Reasoning effort control needs at least one enabled valid option.',
          fr: 'Le contrôle d’effort nécessite au moins une option valide activée.',
          de: 'Die Reasoning-Effort-Steuerung benötigt mindestens eine aktivierte gültige Option.',
          ja: '推論強度制御には少なくとも 1 つの有効な有効化済み選択肢が必要です。',
        );
      });
      return null;
    }
    if (_capabilities.contains(AiModelCapability.readerConversion) &&
        (_readerSourceTypes.isEmpty || _readerTargetTypes.isEmpty)) {
      setState(() {
        _profileErrorMessage = openHandLocalizedText(
          context,
          zh: '读取转换模型至少需要选择一个源文件类型和一个目标文件类型。',
          zhHant: '讀取轉換模型至少需要選擇一個來源檔案類型和一個目標檔案類型。',
          en: 'Read conversion models need at least one source type and one target type.',
          fr: 'Les modèles de conversion doivent avoir au moins un type source et un type cible.',
          de: 'Read-Conversion-Modelle benötigen mindestens einen Quell- und einen Zieltyp.',
          ja: '読み取り変換モデルには、少なくとも 1 つのソース種別と 1 つのターゲット種別が必要です。',
        );
      });
      return null;
    }

    return AiModelProfile(
      displayName: _displayNameController.text.trim().isNotEmpty
          ? _displayNameController.text.trim()
          : null,
      description: _descriptionController.text.trim().isNotEmpty
          ? _descriptionController.text.trim()
          : null,
      isMultimodal: _isMultimodal,
      supportedModalities: _supportedModalities,
      maxContextLength: _oneMillionContextEnabled
          ? AiOneMillionContextPolicy.contextTokens
          : optionalPositiveIntFromText(_maxContextLengthController.text),
      maxSummaryLength: optionalPositiveIntFromText(
        _maxSummaryLengthController.text,
      ),
      maxOutputLength: optionalPositiveIntFromText(
        _maxOutputLengthController.text,
      ),
      maxThinkingLength: optionalPositiveIntFromText(
        _maxThinkingLengthController.text,
      ),
      thinkingEnabled: _thinkingEnabled,
      reasoningEffortControlEnabled: reasoningEffortControlEnabled,
      reasoningEffort: reasoningEffortControlEnabled
          ? normalizedReasoningEffort
          : null,
      reasoningEffortOptions: reasoningEffortOptions,
      requiresReasoningEcho: _requiresReasoningEcho,
      capabilities: _capabilities,
      supportsAttachments: _supportsAttachments,
      inputUsdPer1M: optionalNonNegativeDoubleFromText(
        _inputUsdPer1MController.text,
      ),
      outputUsdPer1M: optionalNonNegativeDoubleFromText(
        _outputUsdPer1MController.text,
      ),
      cacheReadUsdPer1M: optionalNonNegativeDoubleFromText(
        _cacheReadUsdPer1MController.text,
      ),
      cacheWriteUsdPer1M: optionalNonNegativeDoubleFromText(
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
      supportedParameters: _parseCsv(_supportedParametersController.text),
      defaultParameters: defaultParameters,
      isGlobalDefaultTitleModel: _isGlobalDefaultTitleModel,
      embeddingDimensions: optionalPositiveIntFromText(
        _embeddingDimensionsController.text,
      ),
      embeddingMaxInputTokens: optionalPositiveIntFromText(
        _embeddingMaxInputTokensController.text,
      ),
      embeddingSupportsCustomDimensions: _embeddingSupportsCustomDimensions,
      embeddingEndpointPath:
          _embeddingEndpointPathController.text.trim().isNotEmpty
          ? _embeddingEndpointPathController.text.trim()
          : null,
      embeddingBatchSize: optionalPositiveIntFromText(
        _embeddingBatchSizeController.text,
      ),
      embeddingRequiresSpecialBody: _embeddingRequiresSpecialBody,
      embeddingQueryModelId: nullIfBlank(_embeddingQueryModelIdController.text),
      embeddingDocumentModelId: nullIfBlank(
        _embeddingDocumentModelIdController.text,
      ),
      embeddingInputTypes: _parseCsv(_embeddingInputTypesController.text),
      embeddingDefaultInputType: nullIfBlank(
        _embeddingDefaultInputTypeController.text,
      ),
      embeddingQueryInputType: nullIfBlank(
        _embeddingQueryInputTypeController.text,
      ),
      embeddingDocumentInputType: nullIfBlank(
        _embeddingDocumentInputTypeController.text,
      ),
      embeddingSupportedTaskTypes: _parseCsv(
        _embeddingSupportedTaskTypesController.text,
      ),
      embeddingDefaultTaskType: nullIfBlank(
        _embeddingDefaultTaskTypeController.text,
      ),
      embeddingDefaultQueryTaskType: nullIfBlank(
        _embeddingDefaultQueryTaskTypeController.text,
      ),
      embeddingDefaultDocumentTaskType: nullIfBlank(
        _embeddingDefaultDocumentTaskTypeController.text,
      ),
      embeddingQueryTextPrefix: nullIfBlank(
        _embeddingQueryTextPrefixController.text,
      ),
      embeddingDocumentTextPrefix: nullIfBlank(
        _embeddingDocumentTextPrefixController.text,
      ),
      embeddingEncodingFormats: _parseCsv(
        _embeddingEncodingFormatsController.text,
      ),
      embeddingDefaultEncodingFormat: nullIfBlank(
        _embeddingDefaultEncodingFormatController.text,
      ),
      embeddingOutputDTypes: _parseCsv(_embeddingOutputDTypesController.text),
      embeddingDefaultOutputDType: nullIfBlank(
        _embeddingDefaultOutputDTypeController.text,
      ),
      embeddingDefaultTruncation: nullIfBlank(
        _embeddingDefaultTruncationController.text,
      ),
      embeddingSimilarityMetric: nullIfBlank(
        _embeddingSimilarityMetricController.text,
      ),
      embeddingOutputsNormalized: _embeddingOutputsNormalized,
      embeddingMinDimensions: optionalPositiveIntFromText(
        _embeddingMinDimensionsController.text,
      ),
      embeddingMaxDimensions: optionalPositiveIntFromText(
        _embeddingMaxDimensionsController.text,
      ),
      embeddingMaxInputsPerBatch: optionalPositiveIntFromText(
        _embeddingMaxInputsPerBatchController.text,
      ),
      embeddingMaxTokensPerBatch: optionalPositiveIntFromText(
        _embeddingMaxTokensPerBatchController.text,
      ),
      embeddingSupportsTruncation: _embeddingSupportsTruncation,
      readerSourceTypes:
          _capabilities.contains(AiModelCapability.readerConversion)
          ? ReaderFileType.normalizeList(_readerSourceTypes)
          : const <String>[],
      readerTargetTypes:
          _capabilities.contains(AiModelCapability.readerConversion)
          ? ReaderFileType.normalizeList(_readerTargetTypes)
          : const <String>[],
    );
  }

  void _save() {
    final modelId = _validatedModelId();
    if (modelId == null) {
      return;
    }
    final profile = _collectProfile();
    if (profile == null) {
      return;
    }
    Navigator.of(
      context,
    ).pop(_ModelProfileEditorResult(modelId: modelId, profile: profile));
  }

  void _duplicateCurrentModel() {
    final modelId = _validatedModelId();
    if (modelId == null) {
      return;
    }
    final profile = _collectProfile();
    if (profile == null) {
      return;
    }
    final copyModelId = widget.onDuplicate(modelId, profile);
    _reservedModelIds.add(copyModelId);
    if (!mounted) {
      return;
    }
    showOpenHandSuccessSnack(
      context,
      openHandLocalizedText(
        context,
        zh: '已复制模型：$copyModelId',
        zhHant: '已複製模型：$copyModelId',
        en: 'Copied model: $copyModelId',
        fr: 'Modèle copié : $copyModelId',
        de: 'Modell kopiert: $copyModelId',
        ja: 'モデルをコピーしました：$copyModelId',
      ),
      duration: kOpenHandMotion1800,
    );
  }

  void _reset() {
    Navigator.of(context).pop(
      _ModelProfileEditorResult(
        modelId: widget.modelId,
        profile: const AiModelProfile(),
      ),
    );
  }

  void _setOneMillionContextEnabled(bool enabled) {
    if (enabled == _oneMillionContextEnabled) {
      return;
    }
    setState(() {
      if (enabled) {
        _oneMillionContextSnapshot = _OneMillionContextSnapshot(
          modelId: _modelIdController.text,
          maxContextLength: _maxContextLengthController.text,
        );
        _oneMillionContextEnabled = true;
        _syncOneMillionContextFields();
      } else {
        _oneMillionContextEnabled = false;
        _restoreOneMillionContextSnapshot();
      }
      _profileErrorMessage = null;
    });
  }

  void _initializeOneMillionContextState() {
    final initialModelIdText = _modelIdController.text;
    final initialMaxContextText = _maxContextLengthController.text;
    _oneMillionContextEnabled = AiOneMillionContextPolicy.isEnabledBy(
      modelId: initialModelIdText,
      maxContextLength: initialMaxContextText,
      // 目录中的原生 1M 能力不是用户打开的 1M 覆盖开关；仅显式覆盖值可恢复旧版状态。
      includeContextLength:
          widget.initialProfile.maxContextLength ==
          AiOneMillionContextPolicy.contextTokens,
    );
    if (!_oneMillionContextEnabled) {
      return;
    }
    _oneMillionContextSnapshot = _OneMillionContextSnapshot(
      modelId: AiOneMillionContextPolicy.restoreModelId(
        currentModelId: initialModelIdText,
      ),
      maxContextLength: _oneMillionContextFallbackLengthText(
        modelId: initialModelIdText,
        currentMaxContextLength: initialMaxContextText,
      ),
    );
    _syncOneMillionContextFields();
  }

  void _syncOneMillionContextFields() {
    final normalizedModelId = AiOneMillionContextPolicy.normalizeModelId(
      _modelIdController.text,
    );
    if (normalizedModelId.isNotEmpty) {
      _syncControllerText(_modelIdController, normalizedModelId);
    }
    _syncControllerText(
      _maxContextLengthController,
      AiOneMillionContextPolicy.contextTokensText,
    );
  }

  void _restoreOneMillionContextSnapshot() {
    final snapshot = _oneMillionContextSnapshot;
    final restoredModelId = AiOneMillionContextPolicy.restoreModelId(
      currentModelId: _modelIdController.text,
      snapshotModelId: snapshot?.modelId,
    );
    _syncControllerText(_modelIdController, restoredModelId);
    final fallbackContextLength = _oneMillionContextFallbackLengthText(
      modelId: restoredModelId,
      currentMaxContextLength: _maxContextLengthController.text,
    );
    final restoredContextLength =
        AiOneMillionContextPolicy.restoreContextLength(
          currentMaxContextLength: _maxContextLengthController.text,
          snapshotMaxContextLength: snapshot?.maxContextLength,
          fallbackMaxContextLength: fallbackContextLength,
        );
    _syncControllerText(_maxContextLengthController, restoredContextLength);
    _oneMillionContextSnapshot = null;
  }

  String _oneMillionContextFallbackLengthText({
    required String modelId,
    required String currentMaxContextLength,
  }) {
    final current = currentMaxContextLength.trim();
    if (current.isNotEmpty &&
        !AiOneMillionContextPolicy.isPolicyContextLengthText(current)) {
      return current;
    }
    final baseModelId = AiOneMillionContextPolicy.stripModelIdSuffix(modelId);
    final catalogContextLength = AiModelCatalog.lookup(
      baseModelId,
      widget.protocolType,
    )?.maxContextLength;
    final fallbackContextLength =
        catalogContextLength ?? kInferredModelContextWindowTokens;
    return fallbackContextLength.toString();
  }

  Widget _buildGlobalDefaultTitleModelControl() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                openHandLocalizedText(
                  context,
                  zh: '全局默认标题生成模型',
                  zhHant: '全域預設標題生成模型',
                  en: 'Global Default Title Model',
                  fr: 'Modèle de titre global par défaut',
                  de: 'Globales Standardmodell für Titel',
                  ja: 'グローバル既定タイトル生成モデル',
                ),
                style: theme.textTheme.titleSmall,
              ),
              kOpenHandGap4,
              Text(
                openHandLocalizedText(
                  context,
                  zh: '开启后，该模型会作为所有线程标题生成的全局兜底；请选择可生成文本标题的模型，保存时其他模型的同名开关会自动关闭。',
                  zhHant:
                      '開啟後，該模型會作為所有執行緒標題生成的全域兜底；請選擇可生成文字標題的模型，儲存時其他模型的同名開關會自動關閉。',
                  en: 'When enabled, this model becomes the app-wide title fallback. Use a text-capable model; saving turns off the same switch on other models.',
                  fr: 'Activé, ce modèle devient le secours global pour les titres. Choisissez un modèle texte ; l’enregistrement désactive ce choix ailleurs.',
                  de: 'Aktiviert wird dieses Modell zum globalen Titel-Fallback. Nutze ein Textmodell; beim Speichern wird die Option bei anderen Modellen deaktiviert.',
                  ja: '有効にすると、このモデルが全スレッドのタイトル生成フォールバックになります。テキスト対応モデルを選択してください。保存時に他モデルの同名設定はオフになります。',
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        kOpenHandHGap16,
        Switch(
          value: _isGlobalDefaultTitleModel,
          onChanged: (value) {
            setState(() {
              _isGlobalDefaultTitleModel = value;
            });
          },
        ),
      ],
    );
  }

  Widget _buildOneMillionContextControl() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final duration = openHandMotionDuration(context, kOpenHandMotion180);
    final helperText = _oneMillionContextEnabled
        ? openHandLocalizedText(
            context,
            zh: '已锁定上下文长度为 ${AiOneMillionContextPolicy.contextTokensText}，保存时模型 ID 会保持 ${AiOneMillionContextPolicy.modelIdSuffix} 后缀。',
            zhHant:
                '已鎖定上下文長度為 ${AiOneMillionContextPolicy.contextTokensText}，儲存時模型 ID 會保持 ${AiOneMillionContextPolicy.modelIdSuffix} 後綴。',
            en: 'Locks context length to ${AiOneMillionContextPolicy.contextTokensText}; saving keeps the ${AiOneMillionContextPolicy.modelIdSuffix} model ID suffix.',
            fr: 'Verrouille le contexte à ${AiOneMillionContextPolicy.contextTokensText} ; l’ID conserve le suffixe ${AiOneMillionContextPolicy.modelIdSuffix}.',
            de: 'Sperrt die Kontextlänge auf ${AiOneMillionContextPolicy.contextTokensText}; die Modell-ID behält das Suffix ${AiOneMillionContextPolicy.modelIdSuffix}.',
            ja: 'コンテキスト長を ${AiOneMillionContextPolicy.contextTokensText} に固定し、保存時にモデル ID の ${AiOneMillionContextPolicy.modelIdSuffix} 接尾辞を維持します。',
          )
        : openHandLocalizedText(
            context,
            zh: '开启后会自动写入 ${AiOneMillionContextPolicy.contextTokensText}，并为模型 ID 补齐 ${AiOneMillionContextPolicy.modelIdSuffix} 后缀。',
            zhHant:
                '開啟後會自動寫入 ${AiOneMillionContextPolicy.contextTokensText}，並為模型 ID 補齊 ${AiOneMillionContextPolicy.modelIdSuffix} 後綴。',
            en: 'When enabled, writes ${AiOneMillionContextPolicy.contextTokensText} and appends the ${AiOneMillionContextPolicy.modelIdSuffix} model ID suffix.',
            fr: 'Activé, écrit ${AiOneMillionContextPolicy.contextTokensText} et ajoute le suffixe ${AiOneMillionContextPolicy.modelIdSuffix} à l’ID du modèle.',
            de: 'Aktiviert schreibt ${AiOneMillionContextPolicy.contextTokensText} und ergänzt das Suffix ${AiOneMillionContextPolicy.modelIdSuffix} an der Modell-ID.',
            ja: '有効にすると ${AiOneMillionContextPolicy.contextTokensText} を書き込み、モデル ID に ${AiOneMillionContextPolicy.modelIdSuffix} 接尾辞を付けます。',
          );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                openHandLocalizedText(
                  context,
                  zh: '启用 1M 上下文',
                  zhHant: '啟用 1M 上下文',
                  en: 'Enable 1M Context',
                  fr: 'Activer le contexte 1M',
                  de: '1M-Kontext aktivieren',
                  ja: '1M コンテキストを有効化',
                ),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              kOpenHandGap4,
              AnimatedSwitcher(
                duration: duration,
                switchInCurve: kOpenHandSwitchInCurve,
                switchOutCurve: kOpenHandSwitchOutCurve,
                child: Text(
                  helperText,
                  key: ValueKey<bool>(_oneMillionContextEnabled),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        kOpenHandHGap16,
        Switch(
          value: _oneMillionContextEnabled,
          onChanged: _setOneMillionContextEnabled,
        ),
      ],
    );
  }

  Widget _buildThinkingEnabledControl() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final duration = openHandMotionDuration(context, kOpenHandMotion180);
    final helperText = _thinkingEnabled
        ? openHandLocalizedText(
            context,
            zh: '请求时会按该模型所属厂商注入思考/推理开关；不兼容网关会自动降级重试。',
            zhHant: '請求時會依該模型所屬廠商注入思考/推理開關；不相容閘道會自動降級重試。',
            en: 'Requests include the provider-specific thinking switch; incompatible gateways fall back automatically.',
            fr: 'Les requêtes incluent le commutateur de réflexion du fournisseur ; les passerelles incompatibles réessaient sans lui.',
            de: 'Anfragen enthalten den anbieterspezifischen Thinking-Schalter; inkompatible Gateways versuchen es automatisch ohne ihn erneut.',
            ja: 'リクエストにプロバイダー別の思考スイッチを含めます。非対応ゲートウェイは自動的に降級して再試行します。',
          )
        : openHandLocalizedText(
            context,
            zh: '请求时会尽量关闭思考模式；固定推理模型可能仍由服务端保持推理行为。',
            zhHant: '請求時會盡量關閉思考模式；固定推理模型可能仍由服務端保持推理行為。',
            en: 'Requests try to disable thinking; fixed reasoning models may still reason server-side.',
            fr: 'Les requêtes tentent de désactiver la réflexion ; certains modèles raisonnent toujours côté serveur.',
            de: 'Anfragen versuchen Thinking zu deaktivieren; feste Reasoning-Modelle können serverseitig weiterdenken.',
            ja: 'リクエストでは思考を無効化しますが、固定推論モデルではサーバー側で継続される場合があります。',
          );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                openHandLocalizedText(
                  context,
                  zh: '开启思考',
                  zhHant: '開啟思考',
                  en: 'Enable Thinking',
                  fr: 'Activer la réflexion',
                  de: 'Thinking aktivieren',
                  ja: '思考を有効化',
                ),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              kOpenHandGap4,
              AnimatedSwitcher(
                duration: duration,
                switchInCurve: kOpenHandSwitchInCurve,
                switchOutCurve: kOpenHandSwitchOutCurve,
                child: Text(
                  helperText,
                  key: ValueKey<bool>(_thinkingEnabled),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        kOpenHandHGap16,
        Switch(
          value: _thinkingEnabled,
          onChanged: (value) {
            setState(() {
              _thinkingEnabled = value;
              if (!value) {
                _reasoningEffortControlEnabled = false;
              }
            });
          },
        ),
      ],
    );
  }

  Widget _buildReasoningEffortControl() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final duration = openHandMotionDuration(context, kOpenHandMotion180);
    final helperText = !_thinkingEnabled
        ? openHandLocalizedText(
            context,
            zh: '开启思考后才会发送推理强度；关闭思考时该项不会参与请求。',
            zhHant: '開啟思考後才會送出推理強度；關閉思考時此項不參與請求。',
            en: 'Reasoning effort is sent only when thinking is enabled.',
            fr: 'L’effort de raisonnement n’est envoyé que si la réflexion est active.',
            de: 'Reasoning Effort wird nur bei aktiviertem Thinking gesendet.',
            ja: '推論強度は思考が有効な場合のみ送信されます。',
          )
        : _reasoningEffortControlEnabled
        ? openHandLocalizedText(
            context,
            zh: '请求时会把所选原生档位转换为当前厂商的推理强度字段。',
            zhHant: '請求時會將所選原生檔位轉為目前廠商的推理強度欄位。',
            en: 'Requests map the selected native value to this provider’s reasoning-effort field.',
            fr: 'Les requêtes convertissent la valeur native sélectionnée vers le champ d’effort du fournisseur.',
            de: 'Anfragen ordnen den nativen Wert dem Reasoning-Effort-Feld des Anbieters zu.',
            ja: '選択したネイティブ値をプロバイダーの推論強度フィールドにマッピングします。',
          )
        : openHandLocalizedText(
            context,
            zh: '未确认支持推理强度的模型默认关闭；打开后可选择或自定义档位。',
            zhHant: '未確認支援推理強度的模型預設關閉；開啟後可選擇或自訂檔位。',
            en: 'Models without confirmed effort control keep this off by default; enable it to choose or define values.',
            fr: 'Les modèles sans contrôle confirmé le gardent désactivé par défaut.',
            de: 'Modelle ohne bestätigte Effort-Steuerung lassen dies standardmäßig aus.',
            ja: '推論強度制御が未確認のモデルでは既定でオフです。',
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    openHandLocalizedText(
                      context,
                      zh: '启用推理强度控制',
                      zhHant: '啟用推理強度控制',
                      en: 'Enable Reasoning Effort Control',
                      fr: 'Activer le contrôle d’effort',
                      de: 'Reasoning-Effort-Steuerung aktivieren',
                      ja: '推論強度制御を有効化',
                    ),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  kOpenHandGap4,
                  AnimatedSwitcher(
                    duration: duration,
                    switchInCurve: kOpenHandSwitchInCurve,
                    switchOutCurve: kOpenHandSwitchOutCurve,
                    child: Text(
                      helperText,
                      key: ValueKey<String>(
                        'reasoning-effort-$_thinkingEnabled-$_reasoningEffortControlEnabled',
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            kOpenHandHGap16,
            Switch(
              value: _thinkingEnabled && _reasoningEffortControlEnabled,
              onChanged: !_thinkingEnabled
                  ? null
                  : (value) {
                      setState(() {
                        _reasoningEffortControlEnabled = value;
                        if (value) {
                          _ensureReasoningEffortDraft();
                          final options = _currentReasoningEffortOptions();
                          _syncReasoningEffortSelection(options: options);
                        }
                      });
                    },
            ),
          ],
        ),
        AnimatedSwitcher(
          duration: duration,
          switchInCurve: kOpenHandSwitchInCurve,
          switchOutCurve: kOpenHandSwitchOutCurve,
          transitionBuilder: (child, animation) {
            return SizeTransition(
              sizeFactor: animation,
              axisAlignment: -1,
              child: FadeTransition(opacity: animation, child: child),
            );
          },
          child: _reasoningEffortControlEnabled && _thinkingEnabled
              ? Padding(
                  key: const ValueKey<String>('reasoning-effort-fields'),
                  padding: const EdgeInsets.only(top: 12),
                  child: _buildReasoningEffortFields(),
                )
              : const SizedBox.shrink(
                  key: ValueKey<String>('reasoning-effort-fields-hidden'),
                ),
        ),
      ],
    );
  }

  Widget _buildReasoningEffortFields() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final duration = openHandMotionDuration(context, kOpenHandMotion180);
    final options = _currentReasoningEffortOptions();
    final localeName = Localizations.localeOf(context).toLanguageTag();
    final selectedValue = options.any((item) => item.value == _reasoningEffort)
        ? _reasoningEffort
        : (options.isNotEmpty ? options.first.value : null);
    final reasoningEffortActionStyle =
        (theme.filledButtonTheme.style ??
                FilledButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                ))
            .copyWith(
              minimumSize: const WidgetStatePropertyAll(Size(104, 40)),
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 12),
              ),
              shape: const WidgetStatePropertyAll(
                RoundedRectangleBorder(borderRadius: kOpenHandBorderRadius8),
              ),
              textStyle: WidgetStatePropertyAll(
                theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedDropdownButtonFormField<String>(
          key: ValueKey<String?>(
            selectedValue == null ? null : 'reasoning-effort-$selectedValue',
          ),
          initialValue: selectedValue,
          items: options
              .map((option) {
                return DropdownMenuItem<String>(
                  value: option.value,
                  child: Text(
                    option.labelForLocaleName(localeName),
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              })
              .toList(growable: false),
          decoration: InputDecoration(
            labelText: openHandLocalizedText(
              context,
              zh: '推理强度',
              zhHant: '推理強度',
              en: 'Reasoning Effort',
              fr: 'Effort de raisonnement',
              de: 'Reasoning Effort',
              ja: '推論強度',
            ),
            helperText: openHandLocalizedText(
              context,
              zh: '这里保存并发送服务商 API 的原生取值。',
              zhHant: '這裡保存並送出服務商 API 的原生取值。',
              en: 'Stores and sends the provider API’s native value.',
              fr: 'Stocke et envoie la valeur native de l’API fournisseur.',
              de: 'Speichert und sendet den nativen API-Wert des Anbieters.',
              ja: 'プロバイダー API のネイティブ値を保存して送信します。',
            ),
            isDense: true,
          ),
          onChanged: options.isEmpty
              ? null
              : (value) => setState(() => _reasoningEffort = value),
        ),
        kOpenHandGap12,
        Row(
          children: [
            Expanded(
              child: Text(
                openHandLocalizedText(
                  context,
                  zh: '推理强度档位',
                  zhHant: '推理強度檔位',
                  en: 'Reasoning Effort Options',
                  fr: 'Options d’effort',
                  de: 'Reasoning-Effort-Optionen',
                  ja: '推論強度オプション',
                ),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            kOpenHandHGap12,
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                AnimatedPopupMenuButton<AiReasoningEffortPreset>(
                  tooltip: openHandLocalizedText(
                    context,
                    zh: '应用推理档位模板',
                    zhHant: '套用推理檔位範本',
                    en: 'Apply reasoning preset',
                    fr: 'Appliquer un préréglage',
                    de: 'Denkvoreinstellung anwenden',
                    ja: '推論プリセットを適用',
                  ),
                  onSelected: _applyReasoningEffortPreset,
                  constraints: const BoxConstraints(
                    minWidth: 220,
                    maxWidth: 300,
                  ),
                  itemBuilder: (context) => [
                    for (final preset in AiReasoningEffortPreset.all)
                      PopupMenuItem<AiReasoningEffortPreset>(
                        value: preset,
                        child: Row(
                          children: [
                            const Icon(Icons.auto_awesome_rounded, size: 18),
                            kOpenHandHGap10,
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    preset.label,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    preset.options
                                        .map((option) => option.value)
                                        .join(' · '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                  style: reasoningEffortActionStyle,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.auto_awesome_rounded, size: 18),
                      kOpenHandHGap6,
                      Text(
                        openHandLocalizedText(
                          context,
                          zh: '模板',
                          zhHant: '範本',
                          en: 'Presets',
                          fr: 'Préréglages',
                          de: 'Vorlagen',
                          ja: 'プリセット',
                        ),
                      ),
                      kOpenHandHGap2,
                      const Icon(Icons.arrow_drop_down_rounded, size: 18),
                    ],
                  ),
                ),
                MicroPressFeedback(
                  scale: 0.94,
                  child: TextButton.icon(
                    onPressed: _addReasoningEffortOptionDraft,
                    style: reasoningEffortActionStyle,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text(
                      openHandLocalizedText(
                        context,
                        zh: '新增',
                        zhHant: '新增',
                        en: 'Add',
                        fr: 'Ajouter',
                        de: 'Hinzufügen',
                        ja: '追加',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        kOpenHandGap8,
        AnimatedSize(
          duration: duration,
          curve: kOpenHandSwitchInCurve,
          alignment: Alignment.topCenter,
          child: _buildReasoningEffortOptionsList(),
        ),
        if (options.isEmpty) ...[
          kOpenHandGap8,
          Text(
            openHandLocalizedText(
              context,
              zh: '至少启用一个有效档位，或关闭推理强度控制。',
              zhHant: '至少啟用一個有效檔位，或關閉推理強度控制。',
              en: 'Enable at least one valid option, or disable effort control.',
              fr: 'Activez au moins une option valide ou désactivez le contrôle.',
              de: 'Mindestens eine gültige Option aktivieren oder Steuerung deaktivieren.',
              ja: '少なくとも 1 つの有効な選択肢を有効化するか、強度制御を無効にしてください。',
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildReasoningEffortOptionsList() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final height = _reasoningEffortOptionsListHeight();
    return SizedBox(
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLowest.withValues(alpha: 0.72),
          borderRadius: kOpenHandBorderRadius8,
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.58),
          ),
        ),
        child: _reasoningEffortOptionDrafts.isEmpty
            ? OpenHandInlineEmptyState(
                message: openHandLocalizedText(
                  context,
                  zh: '暂无档位，点击新增开始配置。',
                  zhHant: '暫無檔位，點擊新增開始設定。',
                  en: 'No options yet. Add one to start.',
                  fr: 'Aucune option. Ajoutez-en une pour commencer.',
                  de: 'Noch keine Optionen. Füge eine hinzu.',
                  ja: 'オプションはまだありません。追加して設定を始めます。',
                ),
                dense: true,
              )
            : ClipRRect(
                borderRadius: kOpenHandBorderRadius8,
                child: OpenHandSafeScrollbar(
                  controller: _reasoningEffortOptionsScrollController,
                  child: PrimaryScrollController(
                    controller: _reasoningEffortOptionsScrollController,
                    child: ReorderableListView.builder(
                      padding: const EdgeInsets.all(10),
                      buildDefaultDragHandles: false,
                      proxyDecorator: (child, index, animation) =>
                          buildOpenHandReorderProxy(context, child, animation),
                      itemCount: _reasoningEffortOptionDrafts.length,
                      onReorder: _reorderReasoningEffortOptionDrafts,
                      itemBuilder: (context, index) {
                        final draft = _reasoningEffortOptionDrafts[index];
                        return Padding(
                          key: ValueKey<Object>(draft.identity),
                          padding: EdgeInsets.only(
                            bottom:
                                index == _reasoningEffortOptionDrafts.length - 1
                                ? 0
                                : 10,
                          ),
                          child: _buildReasoningEffortOptionDraftEditor(
                            draft: draft,
                            index: index,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildReasoningEffortOptionDraftEditor({
    required _ReasoningEffortOptionDraft draft,
    required int index,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final localeName = Localizations.localeOf(context).toLanguageTag();
    final fallbackTitle = openHandLocalizedText(
      context,
      zh: '档位 ${index + 1}',
      zhHant: '檔位 ${index + 1}',
      en: 'Option ${index + 1}',
      fr: 'Option ${index + 1}',
      de: 'Option ${index + 1}',
      ja: 'オプション ${index + 1}',
    );
    final option = draft.toOption();
    final title = option?.labelForLocaleName(localeName) ?? fallbackTitle;
    final nativeValue = nullIfBlank(draft.valueController.text);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          colorScheme.primary.withValues(alpha: draft.enabled ? 0.035 : 0),
          colorScheme.surfaceContainer,
        ),
        borderRadius: kOpenHandBorderRadius8,
        border: Border.all(
          color: draft.enabled
              ? colorScheme.primary.withValues(alpha: 0.28)
              : colorScheme.outlineVariant.withValues(alpha: 0.72),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ReorderableDragStartListener(
                index: index,
                child: _AiProviderDragHandleFrame(
                  opacity: draft.enabled ? 1 : 0.58,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _AiTtsPriorityBadge(index: index),
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        _AiTtsStatusBadge(enabled: draft.enabled),
                      ],
                    ),
                    kOpenHandGap5,
                    Text(
                      nativeValue ??
                          openHandLocalizedText(
                            context,
                            zh: '未填写原生值',
                            zhHant: '未填寫原生值',
                            en: 'Native value not set',
                            fr: 'Valeur native non définie',
                            de: 'Nativer Wert fehlt',
                            ja: 'ネイティブ値未設定',
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              kOpenHandHGap8,
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.end,
                children: [
                  _buildReasoningEffortRoundActionButton(
                    tooltip: draft.expanded
                        ? openHandLocalizedText(
                            context,
                            zh: '折叠档位',
                            zhHant: '摺疊檔位',
                            en: 'Collapse option',
                            fr: 'Replier l’option',
                            de: 'Option einklappen',
                            ja: 'オプションを折りたたむ',
                          )
                        : openHandLocalizedText(
                            context,
                            zh: '展开档位',
                            zhHant: '展開檔位',
                            en: 'Expand option',
                            fr: 'Déplier l’option',
                            de: 'Option ausklappen',
                            ja: 'オプションを展開',
                          ),
                    icon: AnimatedRotation(
                      turns: draft.expanded ? 0.5 : 0,
                      duration: openHandMotionDuration(
                        context,
                        kOpenHandMotion220,
                      ),
                      curve: kOpenHandSwitchInCurve,
                      child: const Icon(Icons.keyboard_arrow_down_rounded),
                    ),
                    onPressed: () =>
                        _toggleReasoningEffortOptionExpanded(draft),
                  ),
                  _buildReasoningEffortRoundActionButton(
                    tooltip: openHandLocalizedText(
                      context,
                      zh: '删除档位',
                      zhHant: '刪除檔位',
                      en: 'Delete option',
                      fr: 'Supprimer l’option',
                      de: 'Option löschen',
                      ja: 'オプションを削除',
                    ),
                    icon: const Icon(Icons.delete_outline_rounded),
                    foregroundColor: colorScheme.error,
                    backgroundColor: colorScheme.errorContainer.withValues(
                      alpha: 0.36,
                    ),
                    onPressed: () => _removeReasoningEffortOptionDraft(draft),
                  ),
                  _SettingsSwitch(
                    value: draft.enabled,
                    onChanged: (value) =>
                        _setReasoningEffortOptionEnabled(draft, value),
                  ),
                ],
              ),
            ],
          ),
          _AnimatedSettingReveal(
            visible: draft.expanded,
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: _buildReasoningEffortOptionDraftFields(draft),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReasoningEffortOptionDraftFields(
    _ReasoningEffortOptionDraft draft,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 860
            ? 3
            : width >= 560
            ? 2
            : 1;
        final fieldWidth = columns == 1
            ? width
            : (width - 12 * (columns - 1)) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            _buildReasoningEffortDraftTextField(
              width: fieldWidth,
              controller: draft.valueController,
              label: openHandLocalizedText(
                context,
                zh: '原生值',
                zhHant: '原生值',
                en: 'Native Value',
                fr: 'Valeur native',
                de: 'Nativer Wert',
                ja: 'ネイティブ値',
              ),
              onChanged: (_) => setState(() {
                _syncReasoningEffortSelection();
              }),
            ),
            _buildReasoningEffortDraftTextField(
              width: fieldWidth,
              controller: draft.labelZhHansController,
              label: openHandLocalizedText(
                context,
                zh: '简体中文',
                zhHant: '簡體中文',
                en: 'Simplified Chinese',
                fr: 'Chinois simplifié',
                de: 'Vereinfachtes Chinesisch',
                ja: '簡体字中国語',
              ),
            ),
            _buildReasoningEffortDraftTextField(
              width: fieldWidth,
              controller: draft.labelEnController,
              label: 'English',
            ),
            _buildReasoningEffortDraftTextField(
              width: fieldWidth,
              controller: draft.labelZhHantController,
              label: openHandLocalizedText(
                context,
                zh: '繁体中文',
                zhHant: '繁體中文',
                en: 'Traditional Chinese',
                fr: 'Chinois traditionnel',
                de: 'Traditionelles Chinesisch',
                ja: '繁体字中国語',
              ),
            ),
            _buildReasoningEffortDraftTextField(
              width: fieldWidth,
              controller: draft.labelJaController,
              label: '日本語',
            ),
            _buildReasoningEffortDraftTextField(
              width: fieldWidth,
              controller: draft.labelDeController,
              label: 'Deutsch',
            ),
            _buildReasoningEffortDraftTextField(
              width: fieldWidth,
              controller: draft.labelFrController,
              label: 'Français',
            ),
          ],
        );
      },
    );
  }

  Widget _buildReasoningEffortRoundActionButton({
    required String tooltip,
    required Widget icon,
    required VoidCallback onPressed,
    Color? foregroundColor,
    Color? backgroundColor,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: SizedBox.square(
        dimension: 40,
        child: IconButton.filledTonal(
          onPressed: onPressed,
          icon: icon,
          style: IconButton.styleFrom(
            shape: const CircleBorder(),
            padding: EdgeInsets.zero,
            minimumSize: const Size.square(40),
            fixedSize: const Size.square(40),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            backgroundColor:
                backgroundColor ??
                colorScheme.surfaceContainerHighest.withValues(alpha: 0.74),
            foregroundColor: foregroundColor ?? colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _buildReasoningEffortDraftTextField({
    required double width,
    required TextEditingController controller,
    required String label,
    ValueChanged<String>? onChanged,
  }) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        minLines: 1,
        onChanged: onChanged ?? (_) => setState(() {}),
        decoration: InputDecoration(labelText: label, isDense: true),
      ),
    );
  }

  Widget _buildCompactTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
      ),
    );
  }

  Widget _buildReaderTypeChips({
    required String title,
    required List<String> values,
    required Set<String> selected,
    required ValueChanged<Set<String>> onChanged,
  }) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.bodyMedium),
        kOpenHandGap6,
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: <Widget>[
            TextButton.icon(
              onPressed: () {
                onChanged(ReaderFileType.normalizeList(values).toSet());
              },
              icon: const Icon(Icons.done_all_rounded, size: 16),
              label: Text(
                openHandLocalizedText(
                  context,
                  zh: '全选',
                  zhHant: '全選',
                  en: 'Select All',
                  fr: 'Tout sélectionner',
                  de: 'Alle auswählen',
                  ja: 'すべて選択',
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () => onChanged(<String>{}),
              icon: const Icon(Icons.clear_all_rounded, size: 16),
              label: Text(openHandClearLabel(context)),
            ),
          ],
        ),
        kOpenHandGap6,
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final value in values)
              FilterChip(
                label: Text(ReaderFileType.label(value, l10n)),
                selected: selected.contains(value),
                onSelected: (checked) {
                  final next = <String>{...selected};
                  if (checked) {
                    next.add(value);
                  } else {
                    next.remove(value);
                  }
                  onChanged(next);
                },
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildEmbeddingNormalizedControl() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          openHandLocalizedText(
            context,
            zh: '输出向量已归一化',
            zhHant: '輸出向量已正規化',
            en: 'Normalized Output Vectors',
            fr: 'Vecteurs de sortie normalisés',
            de: 'Normalisierte Ausgabevektoren',
            ja: '出力ベクトルは正規化済み',
          ),
          style: theme.textTheme.bodyMedium,
        ),
        kOpenHandGap6,
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: <Widget>[
            ChoiceChip(
              label: Text(
                openHandLocalizedText(
                  context,
                  zh: '未知/自动',
                  zhHant: '未知/自動',
                  en: 'Unknown / Auto',
                  fr: 'Inconnu / auto',
                  de: 'Unbekannt / Auto',
                  ja: '不明 / 自動',
                ),
              ),
              selected: _embeddingOutputsNormalized == null,
              onSelected: (_) =>
                  setState(() => _embeddingOutputsNormalized = null),
            ),
            ChoiceChip(
              label: Text(AppLocalizations.of(context)!.mdlEdYes),
              selected: _embeddingOutputsNormalized == true,
              onSelected: (_) =>
                  setState(() => _embeddingOutputsNormalized = true),
            ),
            ChoiceChip(
              label: Text(AppLocalizations.of(context)!.mdlEdNo),
              selected: _embeddingOutputsNormalized == false,
              onSelected: (_) =>
                  setState(() => _embeddingOutputsNormalized = false),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return buildOpenHandAlertDialog(
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
              TextField(
                controller: _modelIdController,
                decoration: InputDecoration(
                  labelText: openHandModelIdLabel(context),
                  hintText: 'gpt-4o-mini',
                  helperText: openHandLocalizedText(
                    context,
                    zh: '用于请求接口的真实模型标识，必须在当前提供商内唯一。',
                    zhHant: '用於請求介面的真實模型識別，必須在目前提供商內唯一。',
                    en: 'Actual model identifier sent to the API. Must be unique in this provider.',
                    fr: 'Identifiant réel envoyé à l’API. Il doit être unique chez ce fournisseur.',
                    de: 'Tatsächliche Modellkennung für die API. Muss bei diesem Anbieter eindeutig sein.',
                    ja: 'API に送信される実際のモデル識別子です。このプロバイダー内で一意である必要があります。',
                  ),
                  isDense: true,
                ),
                onChanged: (_) {
                  if (_profileErrorMessage == null) return;
                  setState(() => _profileErrorMessage = null);
                },
                onEditingComplete: () {
                  if (_oneMillionContextEnabled) {
                    _syncOneMillionContextFields();
                  }
                  FocusScope.of(context).nextFocus();
                },
              ),
              kOpenHandGap16,
              if (_profileErrorMessage != null) ...[
                Text(
                  _profileErrorMessage!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                kOpenHandGap12,
              ],

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
              kOpenHandGap12,

              // Description
              TextField(
                controller: _descriptionController,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.mdlEdDescription,
                  isDense: true,
                ),
                maxLines: 2,
              ),
              kOpenHandGap16,

              _buildGlobalDefaultTitleModelControl(),
              kOpenHandGap16,

              // Multimodal toggle (tri-state)
              _buildSectionHeader(
                AppLocalizations.of(context)!.mdlEdMultimodalSupport,
              ),
              kOpenHandGap8,
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
              kOpenHandGap16,

              // Supports attachments toggle (tri-state). Drives whether the
              // composer's attachment button is enabled for sessions using
              // this model.
              _buildSectionHeader(
                AppLocalizations.of(context)!.mdlEdSupportsAttachments,
              ),
              kOpenHandGap8,
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
              kOpenHandGap16,

              _buildThinkingEnabledControl(),
              kOpenHandGap16,

              _buildReasoningEffortControl(),
              kOpenHandGap16,

              _buildSectionHeader(
                AppLocalizations.of(context)!.mdlEdReasoningEcho,
              ),
              kOpenHandGap8,
              Text(
                AppLocalizations.of(context)!.mdlEdReasoningEchoHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              kOpenHandGap8,
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
              kOpenHandGap16,

              _buildSectionHeader(
                AppLocalizations.of(context)!.mdlEdSupportedModalities,
              ),
              kOpenHandGap8,
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
              kOpenHandGap16,

              // Capabilities
              _buildSectionHeader(
                AppLocalizations.of(context)!.mdlEdGenerationCapabilities,
              ),
              kOpenHandGap8,
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
                        AiModelCapability.embeddingGeneration =>
                          openHandLocalizedText(
                            context,
                            zh: '嵌入生成',
                            zhHant: '嵌入生成',
                            en: 'Embeddings',
                            fr: 'Embeddings',
                            de: 'Embeddings',
                            ja: '埋め込み生成',
                          ),
                        AiModelCapability.rerank => openHandLocalizedText(
                          context,
                          zh: '重排序',
                          zhHant: '重排序',
                          en: 'Rerank',
                          fr: 'Rerank',
                          de: 'Rerank',
                          ja: '再ランキング',
                        ),
                        AiModelCapability.readerConversion =>
                          openHandLocalizedText(
                            context,
                            zh: '读取转换',
                            zhHant: '讀取轉換',
                            en: 'Read Convert',
                            fr: 'Conversion de lecture',
                            de: 'Lesekonvertierung',
                            ja: '読み取り変換',
                          ),
                      };
                      return FilterChip(
                        label: Text(label),
                        selected: _capabilities.contains(c),
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              _capabilities.add(c);
                              if (c == AiModelCapability.readerConversion) {
                                _ensureDefaultReaderTypes();
                              }
                            } else {
                              _capabilities.remove(c);
                              if (c == AiModelCapability.readerConversion) {
                                _readerSourceTypes.clear();
                                _readerTargetTypes.clear();
                              }
                            }
                          });
                        },
                      );
                    })
                    .toList(growable: false),
              ),
              kOpenHandGap16,

              if (_capabilities.contains(
                AiModelCapability.readerConversion,
              )) ...[
                _buildSectionHeader(
                  openHandLocalizedText(
                    context,
                    zh: '读取转换配置',
                    zhHant: '讀取轉換設定',
                    en: 'Read Conversion',
                    fr: 'Conversion de lecture',
                    de: 'Lesekonvertierung',
                    ja: '読み取り変換設定',
                  ),
                ),
                kOpenHandGap8,
                Text(
                  openHandLocalizedText(
                    context,
                    zh: '配置该模型可读取的源文件类型，以及可转换输出的目标类型。知识库模型解析会按这里的能力筛选模型。',
                    zhHant: '設定該模型可讀取的來源檔案類型，以及可轉換輸出的目標類型。知識庫模型解析會依這裡的能力篩選模型。',
                    en: 'Configure source file types this model can read and target types it can output. Knowledge Base model parsing filters by these capabilities.',
                    fr: 'Configurez les types source lisibles et les types cible produits. La base de connaissances filtre les modèles avec ces capacités.',
                    de: 'Konfiguriere lesbare Quelldateitypen und mögliche Zieltypen. Die Wissensbasis filtert Modelle nach diesen Fähigkeiten.',
                    ja: 'このモデルが読み取れるソースファイル種別と、出力できるターゲット種別を設定します。ナレッジベース解析はこの能力でモデルを絞り込みます。',
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                kOpenHandGap10,
                _buildReaderTypeChips(
                  title: openHandLocalizedText(
                    context,
                    zh: '源文件类型',
                    zhHant: '來源檔案類型',
                    en: 'Source Types',
                    fr: 'Types source',
                    de: 'Quelltypen',
                    ja: 'ソース種別',
                  ),
                  values: ReaderFileType.sourceTypes,
                  selected: _readerSourceTypes,
                  onChanged: (next) =>
                      setState(() => _readerSourceTypes = next),
                ),
                kOpenHandGap12,
                _buildReaderTypeChips(
                  title: openHandLocalizedText(
                    context,
                    zh: '目标文件类型',
                    zhHant: '目標檔案類型',
                    en: 'Target Types',
                    fr: 'Types cible',
                    de: 'Zieltypen',
                    ja: 'ターゲット種別',
                  ),
                  values: ReaderFileType.targetTypes,
                  selected: _readerTargetTypes,
                  onChanged: (next) =>
                      setState(() => _readerTargetTypes = next),
                ),
                kOpenHandGap16,
              ],

              if (_capabilities.contains(
                AiModelCapability.embeddingGeneration,
              )) ...[
                _buildSectionHeader(
                  openHandLocalizedText(
                    context,
                    zh: '嵌入生成配置',
                    zhHant: '嵌入生成設定',
                    en: 'Embedding Configuration',
                    fr: 'Configuration des embeddings',
                    de: 'Embedding-Konfiguration',
                    ja: '埋め込み生成設定',
                  ),
                ),
                kOpenHandGap8,
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingDimensionsController,
                        keyboardType: TextInputType.number,
                        label: openHandLocalizedText(
                          context,
                          zh: '默认维度',
                          zhHant: '預設維度',
                          en: 'Default Dimensions',
                          fr: 'Dimensions par défaut',
                          de: 'Standarddimensionen',
                          ja: 'デフォルト次元',
                        ),
                      ),
                    ),
                    kOpenHandHGap12,
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingMaxInputTokensController,
                        keyboardType: TextInputType.number,
                        label: openHandLocalizedText(
                          context,
                          zh: '单条最大输入 tokens',
                          zhHant: '單筆最大輸入 tokens',
                          en: 'Max Input Tokens',
                          fr: 'Tokens d’entrée max',
                          de: 'Max. Eingabe-Tokens',
                          ja: '最大入力トークン',
                        ),
                      ),
                    ),
                  ],
                ),
                kOpenHandGap12,
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingEndpointPathController,
                        label: openHandLocalizedText(
                          context,
                          zh: '嵌入 endpoint path',
                          zhHant: '嵌入 endpoint path',
                          en: 'Embedding Endpoint Path',
                          fr: 'Chemin endpoint embeddings',
                          de: 'Embedding-Endpoint-Pfad',
                          ja: '埋め込み endpoint path',
                        ),
                        hint: '/v1/embeddings',
                      ),
                    ),
                    kOpenHandHGap12,
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingBatchSizeController,
                        keyboardType: TextInputType.number,
                        label: openHandLocalizedText(
                          context,
                          zh: '建议 batch size',
                          zhHant: '建議 batch size',
                          en: 'Suggested Batch Size',
                          fr: 'Batch size suggéré',
                          de: 'Empfohlene Batch-Größe',
                          ja: '推奨 batch size',
                        ),
                      ),
                    ),
                  ],
                ),
                kOpenHandGap12,
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingQueryModelIdController,
                        label: openHandLocalizedText(
                          context,
                          zh: 'Query 模型 ID',
                          zhHant: 'Query 模型 ID',
                          en: 'Query Model ID',
                          fr: 'ID modèle Query',
                          de: 'Query-Modell-ID',
                          ja: 'Query モデル ID',
                        ),
                        hint: widget.modelId,
                      ),
                    ),
                    kOpenHandHGap12,
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingDocumentModelIdController,
                        label: openHandLocalizedText(
                          context,
                          zh: 'Document 模型 ID',
                          zhHant: 'Document 模型 ID',
                          en: 'Document Model ID',
                          fr: 'ID modèle Document',
                          de: 'Document-Modell-ID',
                          ja: 'Document モデル ID',
                        ),
                        hint: widget.modelId,
                      ),
                    ),
                  ],
                ),
                kOpenHandGap12,
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingMinDimensionsController,
                        keyboardType: TextInputType.number,
                        label: openHandLocalizedText(
                          context,
                          zh: '最小可选维度',
                          zhHant: '最小可選維度',
                          en: 'Min Dimensions',
                          fr: 'Dimensions min',
                          de: 'Min. Dimensionen',
                          ja: '最小次元',
                        ),
                      ),
                    ),
                    kOpenHandHGap12,
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingMaxDimensionsController,
                        keyboardType: TextInputType.number,
                        label: openHandLocalizedText(
                          context,
                          zh: '最大可选维度',
                          zhHant: '最大可選維度',
                          en: 'Max Dimensions',
                          fr: 'Dimensions max',
                          de: 'Max. Dimensionen',
                          ja: '最大次元',
                        ),
                      ),
                    ),
                  ],
                ),
                kOpenHandGap12,
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingInputTypesController,
                        label: openHandLocalizedText(
                          context,
                          zh: '输入类型（逗号分隔）',
                          zhHant: '輸入類型（逗號分隔）',
                          en: 'Input Types (CSV)',
                          fr: 'Types d’entrée (CSV)',
                          de: 'Eingabetypen (CSV)',
                          ja: '入力タイプ（CSV）',
                        ),
                        hint: 'text, image',
                      ),
                    ),
                    kOpenHandHGap12,
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingSupportedTaskTypesController,
                        label: openHandLocalizedText(
                          context,
                          zh: '任务类型（逗号分隔）',
                          zhHant: '任務類型（逗號分隔）',
                          en: 'Task Types (CSV)',
                          fr: 'Types de tâche (CSV)',
                          de: 'Aufgabentypen (CSV)',
                          ja: 'タスクタイプ（CSV）',
                        ),
                        hint: 'retrieval_query, retrieval_document',
                      ),
                    ),
                  ],
                ),
                kOpenHandGap12,
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingDefaultInputTypeController,
                        label: openHandLocalizedText(
                          context,
                          zh: '默认输入类型',
                          zhHant: '預設輸入類型',
                          en: 'Default Input Type',
                          fr: 'Type d’entrée par défaut',
                          de: 'Standard-Eingabetyp',
                          ja: 'デフォルト入力タイプ',
                        ),
                        hint: 'document',
                      ),
                    ),
                    kOpenHandHGap12,
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingQueryInputTypeController,
                        label: openHandLocalizedText(
                          context,
                          zh: 'Query 输入类型',
                          zhHant: 'Query 輸入類型',
                          en: 'Query Input Type',
                          fr: 'Type d’entrée Query',
                          de: 'Query-Eingabetyp',
                          ja: 'Query 入力タイプ',
                        ),
                        hint: 'query',
                      ),
                    ),
                  ],
                ),
                kOpenHandGap12,
                _buildCompactTextField(
                  controller: _embeddingDocumentInputTypeController,
                  label: openHandLocalizedText(
                    context,
                    zh: 'Document 输入类型',
                    zhHant: 'Document 輸入類型',
                    en: 'Document Input Type',
                    fr: 'Type d’entrée Document',
                    de: 'Document-Eingabetyp',
                    ja: 'Document 入力タイプ',
                  ),
                  hint: 'document',
                ),
                kOpenHandGap12,
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingDefaultTaskTypeController,
                        label: openHandLocalizedText(
                          context,
                          zh: '默认任务类型',
                          zhHant: '預設任務類型',
                          en: 'Default Task Type',
                          fr: 'Type de tâche par défaut',
                          de: 'Standard-Aufgabentyp',
                          ja: 'デフォルトタスクタイプ',
                        ),
                        hint: 'retrieval_document',
                      ),
                    ),
                    kOpenHandHGap12,
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingSimilarityMetricController,
                        label: openHandLocalizedText(
                          context,
                          zh: '相似度/距离类型',
                          zhHant: '相似度/距離類型',
                          en: 'Similarity Metric',
                          fr: 'Métrique de similarité',
                          de: 'Ähnlichkeitsmetrik',
                          ja: '類似度メトリック',
                        ),
                        hint: 'cosine',
                      ),
                    ),
                  ],
                ),
                kOpenHandGap12,
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingDefaultQueryTaskTypeController,
                        label: openHandLocalizedText(
                          context,
                          zh: 'Query 任务类型',
                          zhHant: 'Query 任務類型',
                          en: 'Query Task Type',
                          fr: 'Type de tâche Query',
                          de: 'Query-Aufgabentyp',
                          ja: 'Query タスクタイプ',
                        ),
                        hint: 'RETRIEVAL_QUERY',
                      ),
                    ),
                    kOpenHandHGap12,
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingDefaultDocumentTaskTypeController,
                        label: openHandLocalizedText(
                          context,
                          zh: 'Document 任务类型',
                          zhHant: 'Document 任務類型',
                          en: 'Document Task Type',
                          fr: 'Type de tâche Document',
                          de: 'Document-Aufgabentyp',
                          ja: 'Document タスクタイプ',
                        ),
                        hint: 'RETRIEVAL_DOCUMENT',
                      ),
                    ),
                  ],
                ),
                kOpenHandGap12,
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingQueryTextPrefixController,
                        label: openHandLocalizedText(
                          context,
                          zh: 'Query 文本前缀',
                          zhHant: 'Query 文字前綴',
                          en: 'Query Text Prefix',
                          fr: 'Préfixe texte Query',
                          de: 'Query-Textpräfix',
                          ja: 'Query テキスト接頭辞',
                        ),
                        hint: 'query:',
                      ),
                    ),
                    kOpenHandHGap12,
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingDocumentTextPrefixController,
                        label: openHandLocalizedText(
                          context,
                          zh: 'Document 文本前缀',
                          zhHant: 'Document 文字前綴',
                          en: 'Document Text Prefix',
                          fr: 'Préfixe texte Document',
                          de: 'Document-Textpräfix',
                          ja: 'Document テキスト接頭辞',
                        ),
                        hint: 'passage:',
                      ),
                    ),
                  ],
                ),
                kOpenHandGap12,
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingEncodingFormatsController,
                        label: openHandLocalizedText(
                          context,
                          zh: '编码格式（逗号分隔）',
                          zhHant: '編碼格式（逗號分隔）',
                          en: 'Encoding Formats (CSV)',
                          fr: 'Formats d’encodage (CSV)',
                          de: 'Kodierungsformate (CSV)',
                          ja: 'エンコード形式（CSV）',
                        ),
                        hint: 'float, base64',
                      ),
                    ),
                    kOpenHandHGap12,
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingDefaultEncodingFormatController,
                        label: openHandLocalizedText(
                          context,
                          zh: '默认编码格式',
                          zhHant: '預設編碼格式',
                          en: 'Default Encoding Format',
                          fr: 'Format d’encodage par défaut',
                          de: 'Standard-Kodierungsformat',
                          ja: 'デフォルトエンコード形式',
                        ),
                        hint: 'float',
                      ),
                    ),
                  ],
                ),
                kOpenHandGap12,
                _buildCompactTextField(
                  controller: _embeddingDefaultTruncationController,
                  label: openHandLocalizedText(
                    context,
                    zh: '默认截断策略',
                    zhHant: '預設截斷策略',
                    en: 'Default Truncation',
                    fr: 'Troncature par défaut',
                    de: 'Standard-Kürzung',
                    ja: 'デフォルト切り詰め',
                  ),
                  hint: 'END / true',
                ),
                kOpenHandGap12,
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingOutputDTypesController,
                        label: openHandLocalizedText(
                          context,
                          zh: '输出 dtype（逗号分隔）',
                          zhHant: '輸出 dtype（逗號分隔）',
                          en: 'Output DTypes (CSV)',
                          fr: 'DTypes de sortie (CSV)',
                          de: 'Ausgabe-DTypes (CSV)',
                          ja: '出力 dtype（CSV）',
                        ),
                        hint: 'float, int8, uint8, binary',
                      ),
                    ),
                    kOpenHandHGap12,
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingDefaultOutputDTypeController,
                        label: openHandLocalizedText(
                          context,
                          zh: '默认输出 dtype',
                          zhHant: '預設輸出 dtype',
                          en: 'Default Output DType',
                          fr: 'DType de sortie par défaut',
                          de: 'Standard-Ausgabe-DType',
                          ja: 'デフォルト出力 dtype',
                        ),
                        hint: 'float',
                      ),
                    ),
                  ],
                ),
                kOpenHandGap12,
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingMaxInputsPerBatchController,
                        keyboardType: TextInputType.number,
                        label: openHandLocalizedText(
                          context,
                          zh: '每批最大输入数',
                          zhHant: '每批最大輸入數',
                          en: 'Max Inputs Per Batch',
                          fr: 'Entrées max par lot',
                          de: 'Max. Eingaben pro Batch',
                          ja: 'バッチあたり最大入力数',
                        ),
                      ),
                    ),
                    kOpenHandHGap12,
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingMaxTokensPerBatchController,
                        keyboardType: TextInputType.number,
                        label: openHandLocalizedText(
                          context,
                          zh: '每批最大 tokens',
                          zhHant: '每批最大 tokens',
                          en: 'Max Tokens Per Batch',
                          fr: 'Tokens max par lot',
                          de: 'Max. Tokens pro Batch',
                          ja: 'バッチあたり最大トークン',
                        ),
                      ),
                    ),
                  ],
                ),
                kOpenHandGap8,
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    openHandLocalizedText(
                      context,
                      zh: '支持自定义 dimensions / output dimensionality',
                      zhHant: '支援自訂 dimensions / output dimensionality',
                      en: 'Supports Custom Dimensions',
                      fr: 'Prend en charge les dimensions personnalisées',
                      de: 'Unterstützt benutzerdefinierte Dimensionen',
                      ja: 'カスタム dimensions / output dimensionality に対応',
                    ),
                  ),
                  value: _embeddingSupportsCustomDimensions,
                  onChanged: (value) => setState(
                    () => _embeddingSupportsCustomDimensions = value,
                  ),
                ),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    openHandLocalizedText(
                      context,
                      zh: '需要特殊 request body 字段',
                      zhHant: '需要特殊 request body 欄位',
                      en: 'Requires Special Request Body',
                      fr: 'Nécessite un corps de requête spécial',
                      de: 'Benötigt speziellen Request-Body',
                      ja: '特殊な request body フィールドが必要',
                    ),
                  ),
                  value: _embeddingRequiresSpecialBody,
                  onChanged: (value) =>
                      setState(() => _embeddingRequiresSpecialBody = value),
                ),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    openHandLocalizedText(
                      context,
                      zh: '支持服务端自动截断',
                      zhHant: '支援服務端自動截斷',
                      en: 'Supports Server Truncation',
                      fr: 'Prend en charge la troncature serveur',
                      de: 'Unterstützt serverseitige Kürzung',
                      ja: 'サーバー側自動切り詰めに対応',
                    ),
                  ),
                  value: _embeddingSupportsTruncation,
                  onChanged: (value) =>
                      setState(() => _embeddingSupportsTruncation = value),
                ),
                kOpenHandGap4,
                _buildEmbeddingNormalizedControl(),
                kOpenHandGap16,
              ],

              // Token limits
              _buildSectionHeader(
                AppLocalizations.of(context)!.mdlEdTokenLimits,
              ),
              kOpenHandGap8,
              _buildOneMillionContextControl(),
              kOpenHandGap12,
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _maxContextLengthController,
                      readOnly: _oneMillionContextEnabled,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: AppLocalizations.of(
                          context,
                        )!.mdlEdContextLength,
                        suffixIcon: _oneMillionContextEnabled
                            ? Icon(
                                Icons.lock_outline_rounded,
                                size: 18,
                                color: colorScheme.onSurfaceVariant,
                              )
                            : null,
                        suffixIconConstraints: const BoxConstraints(
                          minWidth: 36,
                          minHeight: 36,
                        ),
                        isDense: true,
                      ),
                    ),
                  ),
                  kOpenHandHGap12,
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
              kOpenHandGap12,
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
                  kOpenHandHGap12,
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
              kOpenHandGap16,
              _buildSectionHeader(
                AppLocalizations.of(context)!.mdlEdTokenPricingUsd1mTokensLeave,
              ),
              kOpenHandGap8,
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
                  kOpenHandHGap12,
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
              kOpenHandGap12,
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
                  kOpenHandHGap12,
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
              kOpenHandGap16,
              _buildSectionHeader('OpenRouter Metadata Overrides'),
              kOpenHandGap8,
              TextField(
                controller: _canonicalSlugController,
                decoration: const InputDecoration(
                  labelText: 'canonical_slug',
                  isDense: true,
                ),
              ),
              kOpenHandGap12,
              TextField(
                controller: _huggingFaceIdController,
                decoration: const InputDecoration(
                  labelText: 'hugging_face_id',
                  isDense: true,
                ),
              ),
              kOpenHandGap12,
              TextField(
                controller: _knowledgeCutoffController,
                decoration: const InputDecoration(
                  labelText: 'knowledge_cutoff',
                  isDense: true,
                ),
              ),
              kOpenHandGap12,
              TextField(
                controller: _expirationDateController,
                decoration: const InputDecoration(
                  labelText: 'expiration_date',
                  isDense: true,
                ),
              ),
              kOpenHandGap12,
              TextField(
                controller: _supportedParametersController,
                decoration: const InputDecoration(
                  labelText: 'supported_parameters (CSV)',
                  hintText: 'input, model, input_type, truncate',
                  isDense: true,
                ),
              ),
              kOpenHandGap12,
              TextField(
                controller: _defaultParametersController,
                minLines: 2,
                maxLines: 5,
                onChanged: (_) {
                  if (_profileErrorMessage == null) return;
                  setState(() => _profileErrorMessage = null);
                },
                decoration: const InputDecoration(
                  labelText: 'default_parameters (JSON)',
                  hintText: '{"encoding_format": "float"}',
                  alignLabelWithHint: true,
                  isDense: true,
                ),
              ),
              kOpenHandGap16,
              OpenHandExpansionTile(
                tilePadding: EdgeInsets.zero,
                suppressHoverOverlay: true,
                circularToggle: true,
                title: _buildSectionHeader('OpenRouter Raw Metadata'),
                subtitle: Text(
                  'id / canonical_slug / hugging_face_id / created / architecture / supported_parameters / default_parameters / supported_voices / knowledge_cutoff / expiration_date / links',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                children: [
                  kOpenHandGap8,
                  SelectionArea(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: kOpenHandBorderRadius16,
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
        if (widget.showDuplicateAction)
          OpenHandDialogActionButton.secondary(
            onPressed: _duplicateCurrentModel,
            icon: Icons.copy_rounded,
            label: AppLocalizations.of(context)!.commonCopy,
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
      'reasoning_effort_control_enabled': profile.reasoningEffortControlEnabled,
      'reasoning_effort': profile.reasoningEffort,
      'reasoning_effort_options': profile.reasoningEffortOptions
          .map((item) => item.toJson())
          .toList(growable: false),
      'supported_voices': profile.supportedVoices,
      'knowledge_cutoff': profile.knowledgeCutoff,
      'expiration_date': profile.expirationDate,
      'links': profile.links?.toJson(),
    };
    return prettyPrintJson(map);
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

class _ReasoningEffortOptionsSnapshot {
  const _ReasoningEffortOptionsSnapshot({
    required this.options,
    this.hasIncompleteRow = false,
    this.duplicateValue,
  });

  final List<AiReasoningEffortOption> options;
  final bool hasIncompleteRow;
  final String? duplicateValue;
}

class _EndpointPreviewRow extends StatelessWidget {
  const _EndpointPreviewRow({
    required this.icon,
    required this.label,
    required this.url,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String url;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(kOpenHandRadius9),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        kOpenHandHGap10,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
              kOpenHandGap2,
              Text(
                url,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontFamily: kOpenHandMonospaceFontFamily,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReasoningEffortOptionDraft {
  _ReasoningEffortOptionDraft({
    required String value,
    required this.enabled,
    required this.expanded,
    required String labelZhHans,
    required String labelEn,
    required String labelZhHant,
    required String labelJa,
    required String labelDe,
    required String labelFr,
  }) : valueController = TextEditingController(text: value),
       labelZhHansController = TextEditingController(text: labelZhHans),
       labelEnController = TextEditingController(text: labelEn),
       labelZhHantController = TextEditingController(text: labelZhHant),
       labelJaController = TextEditingController(text: labelJa),
       labelDeController = TextEditingController(text: labelDe),
       labelFrController = TextEditingController(text: labelFr);

  factory _ReasoningEffortOptionDraft.fromOption(
    AiReasoningEffortOption option,
  ) {
    final labelZhHans = option.labelZhHans ?? option.label;
    final labelEn = option.labelEn ?? option.label;
    return _ReasoningEffortOptionDraft(
      value: option.value,
      enabled: option.enabled,
      expanded: false,
      labelZhHans: labelZhHans,
      labelEn: labelEn,
      labelZhHant: option.labelZhHant ?? labelZhHans,
      labelJa: option.labelJa ?? labelEn,
      labelDe: option.labelDe ?? labelEn,
      labelFr: option.labelFr ?? labelEn,
    );
  }

  factory _ReasoningEffortOptionDraft.empty() {
    return _ReasoningEffortOptionDraft(
      value: '',
      enabled: true,
      expanded: true,
      labelZhHans: '',
      labelEn: '',
      labelZhHant: '',
      labelJa: '',
      labelDe: '',
      labelFr: '',
    );
  }

  final Object identity = Object();
  final TextEditingController valueController;
  final TextEditingController labelZhHansController;
  final TextEditingController labelEnController;
  final TextEditingController labelZhHantController;
  final TextEditingController labelJaController;
  final TextEditingController labelDeController;
  final TextEditingController labelFrController;
  bool enabled;
  bool expanded;

  bool get hasAnyText {
    return <TextEditingController>[
      valueController,
      labelZhHansController,
      labelEnController,
      labelZhHantController,
      labelJaController,
      labelDeController,
      labelFrController,
    ].any((controller) => nullIfBlank(controller.text) != null);
  }

  AiReasoningEffortOption? toOption() {
    final value = nullIfBlank(valueController.text);
    if (value == null) return null;
    final labelZhHans = nullIfBlank(labelZhHansController.text);
    final labelEn = nullIfBlank(labelEnController.text);
    final labelZhHant = nullIfBlank(labelZhHantController.text);
    final labelJa = nullIfBlank(labelJaController.text);
    final labelDe = nullIfBlank(labelDeController.text);
    final labelFr = nullIfBlank(labelFrController.text);
    return AiReasoningEffortOption(
      value: value,
      label: labelZhHans ?? labelEn ?? labelZhHant ?? labelJa ?? value,
      enabled: enabled,
      labelZhHans: labelZhHans,
      labelZhHant: labelZhHant,
      labelEn: labelEn,
      labelJa: labelJa,
      labelDe: labelDe,
      labelFr: labelFr,
    );
  }

  void dispose() {
    valueController.dispose();
    labelZhHansController.dispose();
    labelEnController.dispose();
    labelZhHantController.dispose();
    labelJaController.dispose();
    labelDeController.dispose();
    labelFrController.dispose();
  }
}

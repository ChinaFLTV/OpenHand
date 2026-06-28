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
  late String _realtimeCapabilityStatus;
  late String _filesCapabilityStatus;
  late String _fineTunesCapabilityStatus;
  bool _obscureToken = true;
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
          if (_defaultTitleModelId != null &&
              !sorted.contains(_defaultTitleModelId)) {
            _defaultTitleModelId = null;
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
      if (_defaultTitleModelId == modelId) {
        _defaultTitleModelId = null;
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
    final existing = _modelProfiles[modelId] ?? const AiModelProfile();
    final effectiveModel = AiModelConfig(
      id: widget.initialModel?.id ?? '',
      name: _nameController.text.trim(),
      baseUrl: _baseUrlController.text.trim(),
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
      final candidate = '$base-Copy-$index';
      if (!used.contains(candidate)) {
        return candidate;
      }
    }
    return '$base-Copy-${DateTime.now().microsecondsSinceEpoch}';
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

  String _previewChatEndpoint() {
    final baseUrl = _baseUrlController.text.trim();
    if (baseUrl.isEmpty || !isValidHttpUrl(baseUrl)) {
      return '';
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
        endpointOverrides: parseAiEndpointOverrides(
          _tryDecodeJsonObject(_endpointOverridesController.text),
        ),
      );
      return _endpointPreviewRouter
          .resolve(
            config,
            adapter.operationFamily,
            fallbackPath: adapter.endpointPath,
            method: _requestMethod,
          )
          .url;
    } catch (_) {
      return '';
    }
  }

  Widget _buildAutoCompleteBaseUrlControl() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final previewUrl = _previewChatEndpoint();
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(0, 0, 0, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _localizedText(
                    context,
                    zh: '自动补全 Base URL',
                    en: 'Auto-complete Base URL',
                  ),
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  _autoCompleteBaseUrl
                      ? _localizedText(
                          context,
                          zh: '开启时按协议补默认版本路径，例如 OpenAI 兼容接口会追加 v1。',
                          en: 'Adds the protocol default version path, such as v1 for OpenAI-compatible endpoints.',
                        )
                      : _localizedText(
                          context,
                          zh: '关闭时严格使用你填写的 Base URL，只继续拼接资源路径。',
                          en: 'Uses the Base URL exactly, then appends only the resource path.',
                        ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                AnimatedSwitcher(
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: previewUrl.isEmpty
                      ? const SizedBox.shrink(
                          key: ValueKey<String>('endpoint-preview-empty'),
                        )
                      : Padding(
                          key: ValueKey<String>(previewUrl),
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            _localizedText(
                              context,
                              zh: '预览：$previewUrl',
                              en: 'Preview: $previewUrl',
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
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
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 180);
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
                          '启用 Claude 显式提示词缓存点',
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          globalInputCacheEnabled
                              ? '开启后，Claude native 请求会按成本控制设置插入 cache_control 断点。'
                              : '全局输入缓存已关闭；此开关会保存偏好，但当前不会生效。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
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
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: duration,
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
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
          helperText: _localizedText(
            context,
            zh: '请先扫描模型或手动添加模型 ID。',
            en: 'Scan models or add a model ID first.',
          ),
        ),
        child: Text(
          _localizedText(context, zh: '暂无可选模型', en: 'No models available'),
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
    return DropdownButtonFormField<String>(
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
              _localizedText(context, zh: '不设置', en: 'Not set'),
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
    final settingsController = context.watch<SettingsController>();
    final globalInputCacheEnabled = settingsController.aiInputCacheEnabled;

    return PopScope(
      canPop: !_isSaving,
      child: buildOpenHandResponsiveDialogShell(
        context: context,
        maxWidth: 760,
        maxHeight: 860,
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
                            const SizedBox(height: 16),
                            _buildAutoCompleteBaseUrlControl(),
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
                            _buildExplicitPromptCacheControl(
                              globalInputCacheEnabled: globalInputCacheEnabled,
                            ),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 180),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              transitionBuilder: (child, animation) {
                                return SizeTransition(
                                  sizeFactor: animation,
                                  axisAlignment: -1,
                                  child: FadeTransition(
                                    opacity: animation,
                                    child: child,
                                  ),
                                );
                              },
                              child: _usesTokenAuth
                                  ? Column(
                                      key: const ValueKey<String>(
                                        'ai-model-token-field',
                                      ),
                                      children: [
                                        const SizedBox(height: 16),
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
                            const SizedBox(height: 20),
                            // ── Model scan section ──
                            Row(
                              children: [
                                Text(
                                  l10n.aiModelAvailableModels,
                                  style: Theme.of(context).textTheme.titleSmall,
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
                                    style: Theme.of(context).textTheme.bodySmall
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
                                        physics: const ClampingScrollPhysics(),
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
                            const SizedBox(height: 16),
                            _buildModelIdDropdown(
                              label: _localizedText(
                                context,
                                zh: '默认标题生成模型 ID',
                                en: 'Default Title Model ID',
                              ),
                              helperText: _localizedText(
                                context,
                                zh: '当前线程模型不适合生成文本标题时，会优先回退到这里选择的同提供商模型。',
                                en: 'When the thread model is not suitable for text titles, title generation falls back to this sibling provider model first.',
                              ),
                              selectedModelId: _defaultTitleModelId,
                              allowUnset: true,
                              onChanged: _selectDefaultTitleModelId,
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
                                if (optionalPositiveIntFromText(trimmed) ==
                                    null) {
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
                                      const SizedBox(height: 16),
                                      streamToggle,
                                    ],
                                  );
                                }
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                                      const SizedBox(height: 16),
                                      temperatureField,
                                    ],
                                  );
                                }
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                                    DropdownButtonFormField<AiProviderKind>(
                                      initialValue: _providerKind,
                                      decoration: const InputDecoration(
                                        labelText: '服务商类型',
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
                            const SizedBox(height: 12),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final stacked = constraints.maxWidth < 640;
                                Widget dropdown({
                                  required String label,
                                  required String value,
                                  required ValueChanged<String?> onChanged,
                                }) {
                                  return DropdownButtonFormField<String>(
                                    initialValue: value,
                                    decoration: InputDecoration(
                                      labelText: label,
                                    ),
                                    items: const <DropdownMenuItem<String>>[
                                      DropdownMenuItem<String>(
                                        value: 'supported',
                                        child: Text('supported'),
                                      ),
                                      DropdownMenuItem<String>(
                                        value: 'experimental',
                                        child: Text('experimental'),
                                      ),
                                      DropdownMenuItem<String>(
                                        value: 'disabled',
                                        child: Text('disabled'),
                                      ),
                                    ],
                                    onChanged: _isSaving ? null : onChanged,
                                  );
                                }

                                final realtimeDropdown = dropdown(
                                  label: 'Realtime 能力状态',
                                  value: _realtimeCapabilityStatus,
                                  onChanged: (value) {
                                    if (value == null) return;
                                    setState(() {
                                      _realtimeCapabilityStatus = value;
                                    });
                                  },
                                );
                                final filesDropdown = dropdown(
                                  label: 'Files 能力状态',
                                  value: _filesCapabilityStatus,
                                  onChanged: (value) {
                                    if (value == null) return;
                                    setState(() {
                                      _filesCapabilityStatus = value;
                                    });
                                  },
                                );
                                final fineTunesDropdown = dropdown(
                                  label: 'Fine-tunes 能力状态',
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
                                      realtimeDropdown,
                                      const SizedBox(height: 12),
                                      filesDropdown,
                                      const SizedBox(height: 12),
                                      fineTunesDropdown,
                                    ],
                                  );
                                }
                                return Column(
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(child: realtimeDropdown),
                                        const SizedBox(width: 16),
                                        Expanded(child: filesDropdown),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    fineTunesDropdown,
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 20),
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
      baseUrl: _baseUrlController.text.trim(),
      autoCompleteBaseUrl: _autoCompleteBaseUrl,
      authScheme: _authScheme,
      token: _effectiveToken,
      modelId: _modelIdController.text.trim(),
      protocolType: _protocolType,
      apiDialect: _apiDialect,
      providerKind: _providerKind,
      explicitPromptCacheEnabled: _showsExplicitPromptCacheControl
          ? _explicitPromptCacheEnabled
          : false,
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
    throw const FormatException('高级 JSON 配置必须是合法的 JSON 对象。');
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

class _ModelProfileEditorResult {
  const _ModelProfileEditorResult({
    required this.modelId,
    required this.profile,
  });

  final String modelId;
  final AiModelProfile profile;
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
  });

  final String modelId;
  final List<String> existingModelIds;
  final AiModelProfile initialProfile;
  final AiModelProfile effectiveProfile;
  final AiProtocolType protocolType;
  final _DuplicateModelProfileCallback onDuplicate;

  @override
  State<_ModelProfileEditorDialog> createState() =>
      _ModelProfileEditorDialogState();
}

class _ModelProfileEditorDialogState extends State<_ModelProfileEditorDialog> {
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
  bool? _isMultimodal;
  bool? _supportsAttachments;
  bool? _requiresReasoningEcho;
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
      text: _prettyJson(
        p.defaultParameters.isNotEmpty
            ? p.defaultParameters
            : effective.defaultParameters,
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
    final normalizedModelId = widget.modelId.toLowerCase();
    if (normalizedModelId.contains('rerank') ||
        normalizedModelId.contains('reranker')) {
      result.add(AiModelCapability.rerank);
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
    for (final part in value.split(',')) {
      final trimmed = part.trim();
      if (trimmed.isEmpty || !seen.add(trimmed)) continue;
      result.add(trimmed);
    }
    return result;
  }

  Map<String, Object?> _parseJsonObject(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return const <String, Object?>{};
    final decoded = jsonDecode(trimmed);
    if (decoded is Map<String, Object?>) {
      return Map<String, Object?>.from(decoded);
    }
    if (decoded is Map) {
      return Map<String, Object?>.from(decoded);
    }
    throw const FormatException('JSON value must be an object.');
  }

  String _prettyJson(Map<String, Object?> map) {
    if (map.isEmpty) return '';
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  String? _validatedModelId() {
    final modelId = _modelIdController.text.trim();
    if (modelId.isEmpty) {
      setState(() {
        _profileErrorMessage = openHandIsChineseLocale(context)
            ? '模型 ID 不能为空。'
            : 'Model ID cannot be empty.';
      });
      return null;
    }
    final conflicts =
        _reservedModelIds.contains(modelId) && modelId != widget.modelId;
    if (conflicts) {
      setState(() {
        _profileErrorMessage = openHandIsChineseLocale(context)
            ? '模型 ID 已存在，请换一个唯一 ID。'
            : 'Model ID already exists. Use a unique ID.';
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
        _profileErrorMessage = openHandIsChineseLocale(context)
            ? 'default_parameters 必须是合法的 JSON 对象。'
            : 'default_parameters must be a valid JSON object.';
      });
      return null;
    }
    if (_profileErrorMessage != null) {
      setState(() => _profileErrorMessage = null);
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
      maxContextLength: optionalPositiveIntFromText(
        _maxContextLengthController.text,
      ),
      maxSummaryLength: optionalPositiveIntFromText(
        _maxSummaryLengthController.text,
      ),
      maxOutputLength: optionalPositiveIntFromText(
        _maxOutputLengthController.text,
      ),
      maxThinkingLength: optionalPositiveIntFromText(
        _maxThinkingLengthController.text,
      ),
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
    OpenHandSnackBar.showSuccess(
      context,
      openHandIsChineseLocale(context)
          ? '已复制模型：$copyModelId'
          : 'Copied model: $copyModelId',
      duration: const Duration(milliseconds: 1800),
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
                _localizedText(
                  context,
                  zh: '全局默认标题生成模型',
                  en: 'Global Default Title Model',
                ),
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                _localizedText(
                  context,
                  zh: '开启后，该模型会作为所有线程标题生成的全局兜底；请选择可生成文本标题的模型，保存时其他模型的同名开关会自动关闭。',
                  en: 'When enabled, this model becomes the app-wide title fallback. Use a text-capable model; saving turns off the same switch on other models.',
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
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

  Widget _buildEmbeddingNormalizedControl() {
    final theme = Theme.of(context);
    final zh = openHandIsChineseLocale(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          zh ? '输出向量已归一化' : 'Normalized Output Vectors',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: <Widget>[
            ChoiceChip(
              label: Text(zh ? '未知/自动' : 'Unknown / Auto'),
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
    final zh = openHandIsChineseLocale(context);
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
                  labelText: zh ? '模型 ID' : 'Model ID',
                  hintText: 'gpt-4o-mini',
                  helperText: zh
                      ? '用于请求接口的真实模型标识，必须在当前提供商内唯一。'
                      : 'Actual model identifier sent to the API. Must be unique in this provider.',
                  isDense: true,
                ),
                onChanged: (_) {
                  if (_profileErrorMessage == null) return;
                  setState(() => _profileErrorMessage = null);
                },
              ),
              const SizedBox(height: 16),
              if (_profileErrorMessage != null) ...[
                Text(
                  _profileErrorMessage!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
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

              _buildGlobalDefaultTitleModelControl(),
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
                        AiModelCapability.embeddingGeneration =>
                          openHandIsChineseLocale(context)
                              ? '嵌入生成'
                              : 'Embeddings',
                        AiModelCapability.rerank =>
                          openHandIsChineseLocale(context) ? '重排序' : 'Rerank',
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

              if (_capabilities.contains(
                AiModelCapability.embeddingGeneration,
              )) ...[
                _buildSectionHeader(zh ? '嵌入生成配置' : 'Embedding Configuration'),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingDimensionsController,
                        keyboardType: TextInputType.number,
                        label: zh ? '默认维度' : 'Default Dimensions',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingMaxInputTokensController,
                        keyboardType: TextInputType.number,
                        label: zh ? '单条最大输入 tokens' : 'Max Input Tokens',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingEndpointPathController,
                        label: zh
                            ? '嵌入 endpoint path'
                            : 'Embedding Endpoint Path',
                        hint: '/v1/embeddings',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingBatchSizeController,
                        keyboardType: TextInputType.number,
                        label: zh ? '建议 batch size' : 'Suggested Batch Size',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingQueryModelIdController,
                        label: zh ? 'Query 模型 ID' : 'Query Model ID',
                        hint: widget.modelId,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingDocumentModelIdController,
                        label: zh ? 'Document 模型 ID' : 'Document Model ID',
                        hint: widget.modelId,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingMinDimensionsController,
                        keyboardType: TextInputType.number,
                        label: zh ? '最小可选维度' : 'Min Dimensions',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingMaxDimensionsController,
                        keyboardType: TextInputType.number,
                        label: zh ? '最大可选维度' : 'Max Dimensions',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingInputTypesController,
                        label: zh ? '输入类型（逗号分隔）' : 'Input Types (CSV)',
                        hint: 'text, image',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingSupportedTaskTypesController,
                        label: zh ? '任务类型（逗号分隔）' : 'Task Types (CSV)',
                        hint: 'retrieval_query, retrieval_document',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingDefaultInputTypeController,
                        label: zh ? '默认输入类型' : 'Default Input Type',
                        hint: 'document',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingQueryInputTypeController,
                        label: zh ? 'Query 输入类型' : 'Query Input Type',
                        hint: 'query',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildCompactTextField(
                  controller: _embeddingDocumentInputTypeController,
                  label: zh ? 'Document 输入类型' : 'Document Input Type',
                  hint: 'document',
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingDefaultTaskTypeController,
                        label: zh ? '默认任务类型' : 'Default Task Type',
                        hint: 'retrieval_document',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingSimilarityMetricController,
                        label: zh ? '相似度/距离类型' : 'Similarity Metric',
                        hint: 'cosine',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingDefaultQueryTaskTypeController,
                        label: zh ? 'Query 任务类型' : 'Query Task Type',
                        hint: 'RETRIEVAL_QUERY',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingDefaultDocumentTaskTypeController,
                        label: zh ? 'Document 任务类型' : 'Document Task Type',
                        hint: 'RETRIEVAL_DOCUMENT',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingQueryTextPrefixController,
                        label: zh ? 'Query 文本前缀' : 'Query Text Prefix',
                        hint: 'query:',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingDocumentTextPrefixController,
                        label: zh ? 'Document 文本前缀' : 'Document Text Prefix',
                        hint: 'passage:',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingEncodingFormatsController,
                        label: zh ? '编码格式（逗号分隔）' : 'Encoding Formats (CSV)',
                        hint: 'float, base64',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingDefaultEncodingFormatController,
                        label: zh ? '默认编码格式' : 'Default Encoding Format',
                        hint: 'float',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildCompactTextField(
                  controller: _embeddingDefaultTruncationController,
                  label: zh ? '默认截断策略' : 'Default Truncation',
                  hint: 'END / true',
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingOutputDTypesController,
                        label: zh ? '输出 dtype（逗号分隔）' : 'Output DTypes (CSV)',
                        hint: 'float, int8, uint8, binary',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingDefaultOutputDTypeController,
                        label: zh ? '默认输出 dtype' : 'Default Output DType',
                        hint: 'float',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingMaxInputsPerBatchController,
                        keyboardType: TextInputType.number,
                        label: zh ? '每批最大输入数' : 'Max Inputs Per Batch',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingMaxTokensPerBatchController,
                        keyboardType: TextInputType.number,
                        label: zh ? '每批最大 tokens' : 'Max Tokens Per Batch',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    zh
                        ? '支持自定义 dimensions / output dimensionality'
                        : 'Supports Custom Dimensions',
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
                    zh
                        ? '需要特殊 request body 字段'
                        : 'Requires Special Request Body',
                  ),
                  value: _embeddingRequiresSpecialBody,
                  onChanged: (value) =>
                      setState(() => _embeddingRequiresSpecialBody = value),
                ),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(zh ? '支持服务端自动截断' : 'Supports Server Truncation'),
                  value: _embeddingSupportsTruncation,
                  onChanged: (value) =>
                      setState(() => _embeddingSupportsTruncation = value),
                ),
                const SizedBox(height: 4),
                _buildEmbeddingNormalizedControl(),
                const SizedBox(height: 16),
              ],

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
              const SizedBox(height: 12),
              TextField(
                controller: _supportedParametersController,
                decoration: const InputDecoration(
                  labelText: 'supported_parameters (CSV)',
                  hintText: 'input, model, input_type, truncate',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
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

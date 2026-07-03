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
    _officialWebsiteUrlController.dispose();
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
        // A manual scan replaces cached IDs with the provider's current
        // authoritative list; missing active selections are dropped below.
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
      final candidate = _OneMillionContextPolicy.copyModelId(base, index);
      if (!used.contains(candidate)) {
        return candidate;
      }
    }
    return _OneMillionContextPolicy.copyModelId(
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
                          _localizedText(
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
                        const SizedBox(height: 4),
                        Text(
                          globalInputCacheEnabled
                              ? _localizedText(
                                  context,
                                  zh: '开启后，Claude native 请求会按成本控制设置插入 cache_control 断点。',
                                  zhHant:
                                      '開啟後，Claude native 請求會依成本控制設定插入 cache_control 斷點。',
                                  en: 'When enabled, Claude native requests insert cache_control breakpoints based on cost-control settings.',
                                  fr: 'Activé, les requêtes Claude native insèrent des points cache_control selon le contrôle des coûts.',
                                  de: 'Aktiviert fügen Claude-native Anfragen cache_control-Punkte gemäß Kostensteuerung ein.',
                                  ja: '有効にすると、Claude native リクエストにコスト制御設定に基づく cache_control ブレークポイントを挿入します。',
                                )
                              : _localizedText(
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
                              _localizedText(
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
                            const SizedBox(height: 12),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final stacked = constraints.maxWidth < 640;
                                final dialectDropdown =
                                    DropdownButtonFormField<AiApiDialect>(
                                      initialValue: _apiDialect,
                                      decoration: InputDecoration(
                                        labelText: _localizedText(
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
                                    DropdownButtonFormField<AiProviderKind>(
                                      initialValue: _providerKind,
                                      decoration: InputDecoration(
                                        labelText: _localizedText(
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
                              decoration: InputDecoration(
                                labelText: _localizedText(
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
                            const SizedBox(height: 12),
                            TextField(
                              controller: _embeddingModelIdController,
                              enabled: !_isSaving,
                              decoration: InputDecoration(
                                labelText: _localizedText(
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
                            const SizedBox(height: 12),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final stacked = constraints.maxWidth < 640;
                                final moderationField = TextField(
                                  controller: _moderationModelIdController,
                                  enabled: !_isSaving,
                                  decoration: InputDecoration(
                                    labelText: _localizedText(
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
                                    labelText: _localizedText(
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
                                  decoration: InputDecoration(
                                    labelText: _localizedText(
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
                                    labelText: _localizedText(
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
                                  decoration: InputDecoration(
                                    labelText: _localizedText(
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
                                    labelText: _localizedText(
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
                                  decoration: InputDecoration(
                                    labelText: _localizedText(
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
                                    labelText: _localizedText(
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
                                  decoration: InputDecoration(
                                    labelText: _localizedText(
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
                                    labelText: _localizedText(
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
                                    labelText: _localizedText(
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
                              decoration: InputDecoration(
                                labelText: _localizedText(
                                  context,
                                  zh: 'Endpoint Overrides JSON（可选）',
                                  zhHant: 'Endpoint Overrides JSON（選填）',
                                  en: 'Endpoint Overrides JSON (optional)',
                                  fr: 'JSON de surcharge des endpoints (facultatif)',
                                  de: 'Endpoint-Overrides JSON (optional)',
                                  ja: 'Endpoint Overrides JSON（任意）',
                                ),
                                helperText: _localizedText(
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
                            const SizedBox(height: 12),
                            TextField(
                              controller: _operationExtrasController,
                              enabled: !_isSaving,
                              minLines: 4,
                              maxLines: 8,
                              decoration: InputDecoration(
                                labelText: _localizedText(
                                  context,
                                  zh: 'Operation Extras JSON（可选）',
                                  zhHant: 'Operation Extras JSON（選填）',
                                  en: 'Operation Extras JSON (optional)',
                                  fr: 'JSON des extras d’opération (facultatif)',
                                  de: 'Operation-Extras JSON (optional)',
                                  ja: 'Operation Extras JSON（任意）',
                                ),
                                helperText: _localizedText(
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
                                  label: _localizedText(
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
                                  label: _localizedText(
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
                                  label: _localizedText(
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
      officialWebsiteUrl: _officialWebsiteUrlController.text.trim(),
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
    return optionalStringKeyedMapFromJsonText(trimmed) ??
        (throw const FormatException('高级 JSON 配置必须是合法的 JSON 对象。'));
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

class _OneMillionContextPolicy {
  const _OneMillionContextPolicy._();

  static const int contextTokens = 1000000;
  static const String contextTokensText = '1000000';
  static const String modelIdSuffix = '[1M]';
  static final RegExp _modelIdSuffixRunPattern = RegExp(
    r'(?:\s*\[1m\])+$',
    caseSensitive: false,
  );

  static bool isEnabledBy({
    required String modelId,
    required String maxContextLength,
  }) {
    return hasModelIdSuffix(modelId) ||
        optionalPositiveIntFromText(maxContextLength) == contextTokens;
  }

  static bool hasModelIdSuffix(String modelId) {
    return _modelIdSuffixRunPattern.hasMatch(modelId.trim());
  }

  static String normalizeModelId(String modelId) {
    final trimmed = modelId.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    final base = stripModelIdSuffix(trimmed);
    return '${base.isEmpty ? 'model' : base}$modelIdSuffix';
  }

  static String copyModelId(String sourceModelId, int index) {
    final trimmed = sourceModelId.trim();
    final base = trimmed.isEmpty ? 'model' : trimmed;
    if (!hasModelIdSuffix(base)) {
      return '$base-Copy-$index';
    }
    final withoutSuffix = stripModelIdSuffix(base);
    return '${withoutSuffix.isEmpty ? 'model' : withoutSuffix}-Copy-$index$modelIdSuffix';
  }

  static String stripModelIdSuffix(String modelId) {
    return modelId
        .trim()
        .replaceFirst(_modelIdSuffixRunPattern, '')
        .trimRight();
  }
}

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
  late Set<String> _readerSourceTypes;
  late Set<String> _readerTargetTypes;
  bool? _isMultimodal;
  bool? _supportsAttachments;
  bool? _requiresReasoningEcho;
  bool _oneMillionContextEnabled = false;
  String? _modelIdBeforeOneMillionContext;
  String? _maxContextBeforeOneMillionContext;
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
    final initialModelIdText = _modelIdController.text;
    final initialMaxContextText = _maxContextLengthController.text;
    _oneMillionContextEnabled = _OneMillionContextPolicy.isEnabledBy(
      modelId: initialModelIdText,
      maxContextLength: initialMaxContextText,
    );
    if (_oneMillionContextEnabled) {
      final normalizedModelId = _OneMillionContextPolicy.normalizeModelId(
        initialModelIdText,
      );
      final modelIdWillChange =
          normalizedModelId.isNotEmpty &&
          normalizedModelId != initialModelIdText;
      final contextWillChange =
          initialMaxContextText.trim() !=
          _OneMillionContextPolicy.contextTokensText;
      if (modelIdWillChange || contextWillChange) {
        _modelIdBeforeOneMillionContext = initialModelIdText;
        _maxContextBeforeOneMillionContext = initialMaxContextText;
      }
      _syncOneMillionContextFields();
    }
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

  String _prettyJson(Map<String, Object?> map) {
    if (map.isEmpty) return '';
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  String? _validatedModelId() {
    if (_oneMillionContextEnabled) {
      _syncOneMillionContextFields();
    }
    final modelId = _modelIdController.text.trim();
    if (modelId.isEmpty) {
      setState(() {
        _profileErrorMessage = _localizedText(
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
        _profileErrorMessage = _localizedText(
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
        _profileErrorMessage = _localizedText(
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
    if (_capabilities.contains(AiModelCapability.readerConversion) &&
        (_readerSourceTypes.isEmpty || _readerTargetTypes.isEmpty)) {
      setState(() {
        _profileErrorMessage = _localizedText(
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
          ? _OneMillionContextPolicy.contextTokens
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
    OpenHandSnackBar.showSuccess(
      context,
      _localizedText(
        context,
        zh: '已复制模型：$copyModelId',
        zhHant: '已複製模型：$copyModelId',
        en: 'Copied model: $copyModelId',
        fr: 'Modèle copié : $copyModelId',
        de: 'Modell kopiert: $copyModelId',
        ja: 'モデルをコピーしました：$copyModelId',
      ),
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

  void _setOneMillionContextEnabled(bool enabled) {
    if (enabled == _oneMillionContextEnabled) {
      return;
    }
    setState(() {
      if (enabled) {
        _modelIdBeforeOneMillionContext = _modelIdController.text;
        _maxContextBeforeOneMillionContext = _maxContextLengthController.text;
        _oneMillionContextEnabled = true;
        _syncOneMillionContextFields();
      } else {
        _oneMillionContextEnabled = false;
        _restoreOneMillionContextSnapshotIfUnchanged();
      }
      _profileErrorMessage = null;
    });
  }

  void _syncOneMillionContextFields() {
    final normalizedModelId = _OneMillionContextPolicy.normalizeModelId(
      _modelIdController.text,
    );
    if (normalizedModelId.isNotEmpty) {
      _syncControllerText(_modelIdController, normalizedModelId);
    }
    _syncControllerText(
      _maxContextLengthController,
      _OneMillionContextPolicy.contextTokensText,
    );
  }

  void _restoreOneMillionContextSnapshotIfUnchanged() {
    final previousModelId = _modelIdBeforeOneMillionContext;
    if (previousModelId != null &&
        _modelIdController.text.trim() ==
            _OneMillionContextPolicy.normalizeModelId(previousModelId)) {
      _syncControllerText(_modelIdController, previousModelId);
    }
    final previousContext = _maxContextBeforeOneMillionContext;
    if (previousContext != null &&
        _maxContextLengthController.text.trim() ==
            _OneMillionContextPolicy.contextTokensText) {
      _syncControllerText(_maxContextLengthController, previousContext);
    }
    _modelIdBeforeOneMillionContext = null;
    _maxContextBeforeOneMillionContext = null;
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
                  zhHant: '全域預設標題生成模型',
                  en: 'Global Default Title Model',
                  fr: 'Modèle de titre global par défaut',
                  de: 'Globales Standardmodell für Titel',
                  ja: 'グローバル既定タイトル生成モデル',
                ),
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                _localizedText(
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

  Widget _buildOneMillionContextControl() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final helperText = _oneMillionContextEnabled
        ? _localizedText(
            context,
            zh: '已锁定上下文长度为 ${_OneMillionContextPolicy.contextTokensText}，保存时模型 ID 会保持 ${_OneMillionContextPolicy.modelIdSuffix} 后缀。',
            zhHant:
                '已鎖定上下文長度為 ${_OneMillionContextPolicy.contextTokensText}，儲存時模型 ID 會保持 ${_OneMillionContextPolicy.modelIdSuffix} 後綴。',
            en: 'Locks context length to ${_OneMillionContextPolicy.contextTokensText}; saving keeps the ${_OneMillionContextPolicy.modelIdSuffix} model ID suffix.',
            fr: 'Verrouille le contexte à ${_OneMillionContextPolicy.contextTokensText} ; l’ID conserve le suffixe ${_OneMillionContextPolicy.modelIdSuffix}.',
            de: 'Sperrt die Kontextlänge auf ${_OneMillionContextPolicy.contextTokensText}; die Modell-ID behält das Suffix ${_OneMillionContextPolicy.modelIdSuffix}.',
            ja: 'コンテキスト長を ${_OneMillionContextPolicy.contextTokensText} に固定し、保存時にモデル ID の ${_OneMillionContextPolicy.modelIdSuffix} 接尾辞を維持します。',
          )
        : _localizedText(
            context,
            zh: '开启后会自动写入 ${_OneMillionContextPolicy.contextTokensText}，并为模型 ID 补齐 ${_OneMillionContextPolicy.modelIdSuffix} 后缀。',
            zhHant:
                '開啟後會自動寫入 ${_OneMillionContextPolicy.contextTokensText}，並為模型 ID 補齊 ${_OneMillionContextPolicy.modelIdSuffix} 後綴。',
            en: 'When enabled, writes ${_OneMillionContextPolicy.contextTokensText} and appends the ${_OneMillionContextPolicy.modelIdSuffix} model ID suffix.',
            fr: 'Activé, écrit ${_OneMillionContextPolicy.contextTokensText} et ajoute le suffixe ${_OneMillionContextPolicy.modelIdSuffix} à l’ID du modèle.',
            de: 'Aktiviert schreibt ${_OneMillionContextPolicy.contextTokensText} und ergänzt das Suffix ${_OneMillionContextPolicy.modelIdSuffix} an der Modell-ID.',
            ja: '有効にすると ${_OneMillionContextPolicy.contextTokensText} を書き込み、モデル ID に ${_OneMillionContextPolicy.modelIdSuffix} 接尾辞を付けます。',
          );
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
              const SizedBox(height: 4),
              AnimatedSwitcher(
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
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
        const SizedBox(width: 16),
        Switch(
          value: _oneMillionContextEnabled,
          onChanged: _setOneMillionContextEnabled,
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
        const SizedBox(height: 6),
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
                _localizedText(
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
              label: Text(
                _localizedText(
                  context,
                  zh: '清空',
                  zhHant: '清空',
                  en: 'Clear',
                  fr: 'Effacer',
                  de: 'Leeren',
                  ja: 'クリア',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
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
          _localizedText(
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
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: <Widget>[
            ChoiceChip(
              label: Text(
                _localizedText(
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
                  labelText: _localizedText(
                    context,
                    zh: '模型 ID',
                    zhHant: '模型 ID',
                    en: 'Model ID',
                    fr: 'ID du modèle',
                    de: 'Modell-ID',
                    ja: 'モデル ID',
                  ),
                  hintText: 'gpt-4o-mini',
                  helperText: _localizedText(
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
                        AiModelCapability.embeddingGeneration => _localizedText(
                          context,
                          zh: '嵌入生成',
                          zhHant: '嵌入生成',
                          en: 'Embeddings',
                          fr: 'Embeddings',
                          de: 'Embeddings',
                          ja: '埋め込み生成',
                        ),
                        AiModelCapability.rerank => _localizedText(
                          context,
                          zh: '重排序',
                          zhHant: '重排序',
                          en: 'Rerank',
                          fr: 'Rerank',
                          de: 'Rerank',
                          ja: '再ランキング',
                        ),
                        AiModelCapability.readerConversion => _localizedText(
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
              const SizedBox(height: 16),

              if (_capabilities.contains(
                AiModelCapability.readerConversion,
              )) ...[
                _buildSectionHeader(
                  _localizedText(
                    context,
                    zh: '读取转换配置',
                    zhHant: '讀取轉換設定',
                    en: 'Read Conversion',
                    fr: 'Conversion de lecture',
                    de: 'Lesekonvertierung',
                    ja: '読み取り変換設定',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _localizedText(
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
                const SizedBox(height: 10),
                _buildReaderTypeChips(
                  title: _localizedText(
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
                const SizedBox(height: 12),
                _buildReaderTypeChips(
                  title: _localizedText(
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
                const SizedBox(height: 16),
              ],

              if (_capabilities.contains(
                AiModelCapability.embeddingGeneration,
              )) ...[
                _buildSectionHeader(
                  _localizedText(
                    context,
                    zh: '嵌入生成配置',
                    zhHant: '嵌入生成設定',
                    en: 'Embedding Configuration',
                    fr: 'Configuration des embeddings',
                    de: 'Embedding-Konfiguration',
                    ja: '埋め込み生成設定',
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingDimensionsController,
                        keyboardType: TextInputType.number,
                        label: _localizedText(
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
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingMaxInputTokensController,
                        keyboardType: TextInputType.number,
                        label: _localizedText(
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
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingEndpointPathController,
                        label: _localizedText(
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
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingBatchSizeController,
                        keyboardType: TextInputType.number,
                        label: _localizedText(
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
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingQueryModelIdController,
                        label: _localizedText(
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
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingDocumentModelIdController,
                        label: _localizedText(
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
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingMinDimensionsController,
                        keyboardType: TextInputType.number,
                        label: _localizedText(
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
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingMaxDimensionsController,
                        keyboardType: TextInputType.number,
                        label: _localizedText(
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
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingInputTypesController,
                        label: _localizedText(
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
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingSupportedTaskTypesController,
                        label: _localizedText(
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
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingDefaultInputTypeController,
                        label: _localizedText(
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
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingQueryInputTypeController,
                        label: _localizedText(
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
                const SizedBox(height: 12),
                _buildCompactTextField(
                  controller: _embeddingDocumentInputTypeController,
                  label: _localizedText(
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
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingDefaultTaskTypeController,
                        label: _localizedText(
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
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingSimilarityMetricController,
                        label: _localizedText(
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
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingDefaultQueryTaskTypeController,
                        label: _localizedText(
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
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingDefaultDocumentTaskTypeController,
                        label: _localizedText(
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
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingQueryTextPrefixController,
                        label: _localizedText(
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
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingDocumentTextPrefixController,
                        label: _localizedText(
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
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingEncodingFormatsController,
                        label: _localizedText(
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
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingDefaultEncodingFormatController,
                        label: _localizedText(
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
                const SizedBox(height: 12),
                _buildCompactTextField(
                  controller: _embeddingDefaultTruncationController,
                  label: _localizedText(
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
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingOutputDTypesController,
                        label: _localizedText(
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
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingDefaultOutputDTypeController,
                        label: _localizedText(
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
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingMaxInputsPerBatchController,
                        keyboardType: TextInputType.number,
                        label: _localizedText(
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
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildCompactTextField(
                        controller: _embeddingMaxTokensPerBatchController,
                        keyboardType: TextInputType.number,
                        label: _localizedText(
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
                const SizedBox(height: 8),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    _localizedText(
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
                    _localizedText(
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
                    _localizedText(
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
                const SizedBox(height: 4),
                _buildEmbeddingNormalizedControl(),
                const SizedBox(height: 16),
              ],

              // Token limits
              _buildSectionHeader(
                AppLocalizations.of(context)!.mdlEdTokenLimits,
              ),
              const SizedBox(height: 8),
              _buildOneMillionContextControl(),
              const SizedBox(height: 12),
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

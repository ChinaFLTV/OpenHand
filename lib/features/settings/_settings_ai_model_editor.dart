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
  late AiAuthScheme _authScheme;
  late AiProtocolType _protocolType;
  bool _obscureToken = true;
  bool _isSaving = false;
  bool _isScanning = false;
  String? _errorMessage;
  String? _scanError;
  List<String> _availableModelIds = const <String>[];
  String? _activeModelId;

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
    _authScheme = widget.initialModel?.authScheme ?? AiAuthScheme.bearer;
    _protocolType = widget.initialModel?.protocolType ?? AiProtocolType.openai;
    _availableModelIds = List<String>.from(
      widget.initialModel?.availableModelIds ?? const <String>[],
    );
    _activeModelId = widget.initialModel?.modelId.trim().isNotEmpty == true
        ? widget.initialModel!.modelId.trim()
        : null;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _baseUrlController.dispose();
    _tokenController.dispose();
    _modelIdController.dispose();
    _maxContextTokensController.dispose();
    _manualModelIdController.dispose();
    super.dispose();
  }

  String _localizedText({required String zh, required String en}) {
    final languageCode = Localizations.localeOf(context).languageCode;
    return languageCode.startsWith('zh') ? zh : en;
  }

  Future<void> _scanModels() async {
    final baseUrl = _baseUrlController.text.trim();
    if (baseUrl.isEmpty || !isValidHttpUrl(baseUrl)) {
      setState(() {
        _scanError = _localizedText(
          zh: '请先输入有效的 Base URL',
          en: 'Enter a valid Base URL first',
        );
      });
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
      );
      final result = await scanner.scan(config);
      if (!mounted) return;

      if (result.isSuccess) {
        final merged = <String>{..._availableModelIds, ...result.modelIds};
        final sorted = merged.toList()..sort();
        setState(() {
          _availableModelIds = sorted;
          _isScanning = false;
          _scanError = result.modelIds.isEmpty
              ? _localizedText(
                  zh: '未从该提供商扫描到模型。',
                  en: 'No models found from this provider.',
                )
              : null;
          // Auto-select first model if none currently selected.
          if (_activeModelId == null && sorted.isNotEmpty) {
            _activeModelId = sorted.first;
            _modelIdController.text = sorted.first;
          }
        });
      } else {
        setState(() {
          _isScanning = false;
          _scanError = result.error;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isScanning = false;
        _scanError = '$e';
      });
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
      _availableModelIds = [..._availableModelIds, manualId]..sort();
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
      _availableModelIds = _availableModelIds
          .where((id) => id != modelId)
          .toList(growable: false);
      if (_activeModelId == modelId) {
        _activeModelId = _availableModelIds.isNotEmpty
            ? _availableModelIds.first
            : null;
        _modelIdController.text = _activeModelId ?? '';
      }
    });
  }

  void _selectModelId(String modelId) {
    setState(() {
      _activeModelId = modelId;
      _modelIdController.text = modelId;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: !_isSaving,
      child: Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760, maxHeight: 780),
          child: Padding(
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
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextFormField(
                            controller: _nameController,
                            enabled: !_isSaving,
                            decoration: InputDecoration(
                              labelText: _localizedText(
                                zh: '提供商名称',
                                en: 'Provider Name',
                              ),
                              hintText: _localizedText(
                                zh: '可选，如 DeepSeek、本地 Ollama',
                                en: 'Optional, e.g. DeepSeek, Local Ollama',
                              ),
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
                                              DropdownMenuItem<AiProtocolType>(
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
                                              _protocolType = value;
                                            });
                                          },
                                  );
                              if (stacked) {
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: colorScheme.error),
                            ),
                          ],
                          const SizedBox(height: 12),
                          // Available models chip list
                          if (_availableModelIds.isNotEmpty)
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 160),
                              child: SingleChildScrollView(
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: _availableModelIds
                                      .map(
                                        (id) => InputChip(
                                          label: Text(id),
                                          selected: id == _activeModelId,
                                          onSelected: _isSaving
                                              ? null
                                              : (_) => _selectModelId(id),
                                          onDeleted: _isSaving
                                              ? null
                                              : () => _removeModelId(id),
                                          deleteIcon: const Icon(
                                            Icons.close,
                                            size: 16,
                                          ),
                                        ),
                                      )
                                      .toList(growable: false),
                                ),
                              ),
                            )
                          else
                            Text(
                              _localizedText(
                                zh: '点击「扫描模型」按钮自动发现可用模型，或手动添加。',
                                en: 'Tap "Scan Models" to discover models automatically, or add manually below.',
                              ),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
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
                                onPressed: _isSaving ? null : _addManualModelId,
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
                              labelText: _localizedText(
                                zh: '当前活跃模型 ID',
                                en: 'Active Model ID',
                              ),
                              helperText: _localizedText(
                                zh: '当前用于对话的模型。可从上方列表选择或直接输入。',
                                en: 'The model used for conversations. Select from the list above or type directly.',
                              ),
                            ),
                            onChanged: (value) {
                              setState(() {
                                _activeModelId =
                                    value.trim().isEmpty ? null : value.trim();
                              });
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _maxContextTokensController,
                            enabled: !_isSaving,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: _localizedText(
                                zh: '最大上下文 Token 上限',
                                en: 'Max Context Tokens',
                              ),
                              helperText: _localizedText(
                                zh: '可选。用于在压缩时限制历史切片大小。',
                                en: 'Optional. Limits the history slice used during compression.',
                              ),
                            ),
                            validator: (value) {
                              final trimmed = value?.trim() ?? '';
                              if (trimmed.isEmpty) {
                                return null;
                              }
                              final parsed = int.tryParse(trimmed);
                              if (parsed == null || parsed <= 0) {
                                return _localizedText(
                                  zh: '请输入大于 0 的整数',
                                  en: 'Enter a whole number greater than 0',
                                );
                              }
                              return null;
                            },
                          ),
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
                  mainAxisAlignment: MainAxisAlignment.end,
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
      maxContextTokens: _parseOptionalPositiveInt(
        _maxContextTokensController.text,
      ),
      availableModelIds: _availableModelIds,
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
}

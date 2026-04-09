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
  late String _requestMethod;
  late bool _streamEnabled;
  bool _obscureToken = true;
  bool _isSaving = false;
  bool _isScanning = false;
  String? _errorMessage;
  String? _scanError;
  List<String> _availableModelIds = const <String>[];
  String? _activeModelId;
  late List<_HeaderEntry> _customHeaderEntries;

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
    _requestMethod = widget.initialModel?.requestMethod ?? 'POST';
    _streamEnabled = widget.initialModel?.streamEnabled ?? true;
    _availableModelIds = List<String>.from(
      widget.initialModel?.availableModelIds ?? const <String>[],
    );
    _activeModelId = widget.initialModel?.modelId.trim().isNotEmpty == true
        ? widget.initialModel!.modelId.trim()
        : null;
    _customHeaderEntries = <_HeaderEntry>[];
    final existingHeaders = widget.initialModel?.customHeaders ?? const <String, String>{};
    for (final entry in existingHeaders.entries) {
      _customHeaderEntries.add(_HeaderEntry(
        keyController: TextEditingController(text: entry.key),
        valueController: TextEditingController(text: entry.value),
      ));
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
    for (final entry in _customHeaderEntries) {
      entry.keyController.dispose();
      entry.valueController.dispose();
    }
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
        customHeaders: _collectCustomHeaders(),
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

  void _addHeaderEntry() {
    setState(() {
      _customHeaderEntries.add(_HeaderEntry(
        keyController: TextEditingController(),
        valueController: TextEditingController(),
      ));
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
                                        (id) {
                                          final isActive =
                                              id == _activeModelId;
                                          final colorScheme =
                                              Theme.of(context).colorScheme;
                                          return InputChip(
                                            label: Text(
                                              id,
                                              style: isActive
                                                  ? TextStyle(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: colorScheme
                                                          .primary,
                                                    )
                                                  : null,
                                            ),
                                            avatar: isActive
                                                ? Icon(
                                                    Icons.check_rounded,
                                                    size: 16,
                                                    color:
                                                        colorScheme.primary,
                                                  )
                                                : null,
                                            selected: isActive,
                                            selectedColor: colorScheme
                                                .secondaryContainer,
                                            showCheckmark: false,
                                            side: isActive
                                                ? BorderSide(
                                                    color: colorScheme
                                                        .primary
                                                        .withValues(
                                                          alpha: 0.5,
                                                        ),
                                                  )
                                                : null,
                                            onSelected: _isSaving
                                                ? null
                                                : (_) =>
                                                    _selectModelId(id),
                                            onDeleted: _isSaving
                                                ? null
                                                : () =>
                                                    _removeModelId(id),
                                            deleteIcon: const Icon(
                                              Icons.close,
                                              size: 16,
                                            ),
                                          );
                                        },
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
                          const SizedBox(height: 16),
                          // ── Request configuration section ──
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final stacked = constraints.maxWidth < 640;
                              final methodDropdown = DropdownButtonFormField<String>(
                                initialValue: _requestMethod,
                                decoration: InputDecoration(
                                  labelText: _localizedText(
                                    zh: '请求方式',
                                    en: 'Request Method',
                                  ),
                                ),
                                items: const <DropdownMenuItem<String>>[
                                  DropdownMenuItem<String>(value: 'POST', child: Text('POST')),
                                  DropdownMenuItem<String>(value: 'GET', child: Text('GET')),
                                  DropdownMenuItem<String>(value: 'PUT', child: Text('PUT')),
                                  DropdownMenuItem<String>(value: 'PATCH', child: Text('PATCH')),
                                  DropdownMenuItem<String>(value: 'DELETE', child: Text('DELETE')),
                                  DropdownMenuItem<String>(value: 'HEAD', child: Text('HEAD')),
                                  DropdownMenuItem<String>(value: 'OPTIONS', child: Text('OPTIONS')),
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
                                  labelText: _localizedText(
                                    zh: '输出模式',
                                    en: 'Output Mode',
                                  ),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.only(top: 8),
                                ),
                                child: Row(
                                  children: [
                                    Text(
                                      _streamEnabled
                                          ? _localizedText(zh: '流式输出', en: 'Streaming')
                                          : _localizedText(zh: '非流式输出', en: 'Non-streaming'),
                                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                                  labelText: _localizedText(
                                    zh: '最大输出 Token 数',
                                    en: 'Max Output Tokens',
                                  ),
                                  helperText: _localizedText(
                                    zh: '可选。不指定则使用适配器默认值。',
                                    en: 'Optional. Uses adapter default if unset.',
                                  ),
                                ),
                                validator: (value) {
                                  final trimmed = value?.trim() ?? '';
                                  if (trimmed.isEmpty) return null;
                                  final parsed = int.tryParse(trimmed);
                                  if (parsed == null || parsed <= 0) {
                                    return _localizedText(
                                      zh: '请输入大于 0 的整数',
                                      en: 'Enter a whole number greater than 0',
                                    );
                                  }
                                  return null;
                                },
                              );
                              final temperatureField = TextFormField(
                                controller: _temperatureController,
                                enabled: !_isSaving,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: InputDecoration(
                                  labelText: _localizedText(
                                    zh: '温度',
                                    en: 'Temperature',
                                  ),
                                  helperText: _localizedText(
                                    zh: '0.0 ~ 2.0，默认 0.7',
                                    en: '0.0 ~ 2.0, default 0.7',
                                  ),
                                ),
                                validator: (value) {
                                  final trimmed = value?.trim() ?? '';
                                  if (trimmed.isEmpty) return null;
                                  final parsed = double.tryParse(trimmed);
                                  if (parsed == null || parsed < 0 || parsed > 2.0) {
                                    return _localizedText(
                                      zh: '请输入 0.0 到 2.0 之间的数值',
                                      en: 'Enter a number between 0.0 and 2.0',
                                    );
                                  }
                                  return null;
                                },
                              );
                              if (stacked) {
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                          // ── Custom headers section ──
                          Row(
                            children: [
                              Text(
                                _localizedText(
                                  zh: '自定义请求头',
                                  en: 'Custom Headers',
                                ),
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const Spacer(),
                              FilledButton.tonalIcon(
                                onPressed: _isSaving ? null : _addHeaderEntry,
                                icon: const Icon(Icons.add, size: 18),
                                label: Text(_localizedText(zh: '添加', en: 'Add')),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (_customHeaderEntries.isEmpty)
                            Text(
                              _localizedText(
                                zh: '暂无自定义请求头。点击「添加」按钮来添加。',
                                en: 'No custom headers. Tap "Add" to create one.',
                              ),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: colorScheme.onSurfaceVariant),
                            )
                          else
                            ..._customHeaderEntries.asMap().entries.map((mapEntry) {
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
                                          labelText: _localizedText(
                                            zh: 'Header 名称',
                                            en: 'Header Name',
                                          ),
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
                                          labelText: _localizedText(
                                            zh: 'Header 值',
                                            en: 'Header Value',
                                          ),
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
      customHeaders: _collectCustomHeaders(),
      requestMethod: _requestMethod,
      maxTokens: _parseOptionalPositiveInt(_maxTokensController.text),
      temperature: _parseOptionalDouble(_temperatureController.text),
      streamEnabled: _streamEnabled,
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

  double? _parseOptionalDouble(String rawValue) {
    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) return null;
    return double.tryParse(trimmed);
  }
}

class _HeaderEntry {
  _HeaderEntry({
    required this.keyController,
    required this.valueController,
  });

  final TextEditingController keyController;
  final TextEditingController valueController;
}

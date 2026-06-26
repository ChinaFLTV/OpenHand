import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/state/settings_controller.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/openhand_model_selector_field.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/util/localized_text.dart';
import '../../ai/index.dart';
import '../knowledge_base_controller.dart';
import '../model/knowledge_base_settings.dart';

Future<void> showKnowledgeBaseConfigDialog(BuildContext context) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => const KnowledgeBaseConfigDialog(),
  );
}

class KnowledgeBaseConfigDialog extends StatefulWidget {
  const KnowledgeBaseConfigDialog({super.key});

  @override
  State<KnowledgeBaseConfigDialog> createState() =>
      _KnowledgeBaseConfigDialogState();
}

class _KnowledgeBaseConfigDialogState extends State<KnowledgeBaseConfigDialog> {
  late KnowledgeBaseSettings _settings;
  late final TextEditingController _dimensions;
  late final TextEditingController _maxInputTokens;
  late final TextEditingController _batchSize;
  late final TextEditingController _timeout;
  late final TextEditingController _qdrantHost;
  late final TextEditingController _qdrantRestPort;
  late final TextEditingController _qdrantGrpcPort;
  late final TextEditingController _collectionName;
  late final TextEditingController _targetTokens;
  late final TextEditingController _hardMaxTokens;
  late final TextEditingController _overlapTokens;
  late final TextEditingController _topN;
  late final TextEditingController _topK;
  late final TextEditingController _minSimilarity;
  late final TextEditingController _sourceCap;
  late final TextEditingController _vectorWeight;
  late final TextEditingController _titleWeight;
  late final TextEditingController _tagWeight;
  late final TextEditingController _timeWeight;
  late final TextEditingController _maxPromptChunks;
  late final TextEditingController _maxPromptTokens;

  @override
  void initState() {
    super.initState();
    _settings = context.read<KnowledgeBaseController>().settings;
    _dimensions = TextEditingController(text: '${_settings.dimensions}');
    _maxInputTokens = TextEditingController(
      text: '${_settings.maxInputTokens}',
    );
    _batchSize = TextEditingController(text: '${_settings.batchSize}');
    _timeout = TextEditingController(
      text: '${_settings.requestTimeoutSeconds}',
    );
    _qdrantHost = TextEditingController(text: _settings.qdrantHost);
    _qdrantRestPort = TextEditingController(
      text: '${_settings.qdrantRestPort}',
    );
    _qdrantGrpcPort = TextEditingController(
      text: '${_settings.qdrantGrpcPort}',
    );
    _collectionName = TextEditingController(text: _settings.collectionName);
    _targetTokens = TextEditingController(text: '${_settings.targetTokens}');
    _hardMaxTokens = TextEditingController(text: '${_settings.hardMaxTokens}');
    _overlapTokens = TextEditingController(text: '${_settings.overlapTokens}');
    _topN = TextEditingController(text: '${_settings.topN}');
    _topK = TextEditingController(text: '${_settings.topK}');
    _minSimilarity = TextEditingController(text: '${_settings.minSimilarity}');
    _sourceCap = TextEditingController(text: '${_settings.sourceCap}');
    _vectorWeight = TextEditingController(text: '${_settings.vectorWeight}');
    _titleWeight = TextEditingController(text: '${_settings.titleWeight}');
    _tagWeight = TextEditingController(text: '${_settings.tagWeight}');
    _timeWeight = TextEditingController(text: '${_settings.timeWeight}');
    _maxPromptChunks = TextEditingController(
      text: '${_settings.maxPromptChunks}',
    );
    _maxPromptTokens = TextEditingController(
      text: '${_settings.maxPromptTokens}',
    );
  }

  @override
  void dispose() {
    for (final controller in <TextEditingController>[
      _dimensions,
      _maxInputTokens,
      _batchSize,
      _timeout,
      _qdrantHost,
      _qdrantRestPort,
      _qdrantGrpcPort,
      _collectionName,
      _targetTokens,
      _hardMaxTokens,
      _overlapTokens,
      _topN,
      _topK,
      _minSimilarity,
      _sourceCap,
      _vectorWeight,
      _titleWeight,
      _tagWeight,
      _timeWeight,
      _maxPromptChunks,
      _maxPromptTokens,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  List<AiModelConfig> _embeddingModels(List<AiModelConfig> models) {
    final filtered = <AiModelConfig>[];
    for (final model in models) {
      final ids = model.allModelIds
          .where((id) => model.profileFor(id).supportsEmbeddings)
          .toList(growable: false);
      if (ids.isEmpty) continue;
      filtered.add(
        model.copyWith(
          modelId: ids.contains(model.modelId) ? model.modelId : ids.first,
          availableModelIds: ids,
          defaultTitleModelId: '',
        ),
      );
    }
    return filtered;
  }

  int _int(TextEditingController controller, int fallback) {
    final parsed = int.tryParse(controller.text.trim());
    return parsed == null || parsed <= 0 ? fallback : parsed;
  }

  double _double(TextEditingController controller, double fallback) {
    final parsed = double.tryParse(controller.text.trim());
    if (parsed == null || parsed.isNaN || !parsed.isFinite) return fallback;
    return parsed;
  }

  Future<void> _save() async {
    final next = _settings.copyWith(
      dimensions: _int(_dimensions, _settings.dimensions),
      maxInputTokens: _int(_maxInputTokens, _settings.maxInputTokens),
      batchSize: _int(_batchSize, _settings.batchSize),
      requestTimeoutSeconds: _int(_timeout, _settings.requestTimeoutSeconds),
      qdrantHost: _qdrantHost.text.trim().isEmpty
          ? _settings.qdrantHost
          : _qdrantHost.text.trim(),
      qdrantRestPort: _int(_qdrantRestPort, _settings.qdrantRestPort),
      qdrantGrpcPort: _int(_qdrantGrpcPort, _settings.qdrantGrpcPort),
      collectionName: _collectionName.text.trim(),
      targetTokens: _int(_targetTokens, _settings.targetTokens),
      hardMaxTokens: _int(_hardMaxTokens, _settings.hardMaxTokens),
      overlapTokens:
          int.tryParse(_overlapTokens.text.trim()) ?? _settings.overlapTokens,
      topN: _int(_topN, _settings.topN),
      topK: _int(_topK, _settings.topK),
      minSimilarity: _double(_minSimilarity, _settings.minSimilarity),
      sourceCap: _int(_sourceCap, _settings.sourceCap),
      vectorWeight: _double(_vectorWeight, _settings.vectorWeight),
      titleWeight: _double(_titleWeight, _settings.titleWeight),
      tagWeight: _double(_tagWeight, _settings.tagWeight),
      timeWeight: _double(_timeWeight, _settings.timeWeight),
      maxPromptChunks: _int(_maxPromptChunks, _settings.maxPromptChunks),
      maxPromptTokens: _int(_maxPromptTokens, _settings.maxPromptTokens),
    );
    await context.read<KnowledgeBaseController>().updateSettings(next);
    if (!mounted) return;
    Navigator.of(context).pop();
    OpenHandSnackBar.showSuccess(
      context,
      openHandLocalizedText(
        context,
        zh: '知识库配置已保存。',
        en: 'Knowledge Base settings saved.',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settingsController = context.watch<SettingsController>();
    final models = _embeddingModels(settingsController.aiModels);
    final isZh = openHandIsChineseLocale(context);
    return buildOpenHandAlertDialog(
      title: Text(isZh ? '知识库配置' : 'Knowledge Base Settings'),
      content: buildOpenHandDialogConstrainedContent(
        width: 760,
        maxHeight: MediaQuery.sizeOf(context).height * 0.82,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _section(
                context,
                title: isZh ? '嵌入模型' : 'Embedding Model',
                icon: Icons.hub_outlined,
                children: [
                  if (models.isEmpty)
                    _emptyModelState(context)
                  else
                    SizedBox(
                      width: 700,
                      child: OpenHandModelSelectorField(
                        models: models,
                        recentSelections:
                            settingsController.recentModelSelections,
                        selectedConfigId: _settings.providerConfigId,
                        selectedModelId: _settings.modelId,
                        required: true,
                        labelZh: '嵌入模型',
                        labelEn: 'Embedding model',
                        helperZh: '仅显示已开启“嵌入生成”的模型配置。',
                        helperEn:
                            'Only embedding-capable model profiles are shown.',
                        onSelected: (selection) {
                          final model = models.firstWhere(
                            (item) => item.id == selection.$1,
                          );
                          final profile = model.profileFor(selection.$2);
                          setState(() {
                            _settings = _settings.copyWith(
                              providerConfigId: selection.$1,
                              modelId: selection.$2,
                              displayName: profile.displayName ?? selection.$2,
                              dimensions:
                                  profile.embeddingDimensions ??
                                  _settings.dimensions,
                              maxInputTokens:
                                  profile.embeddingMaxInputTokens ??
                                  _settings.maxInputTokens,
                              batchSize:
                                  profile.embeddingBatchSize ??
                                  _settings.batchSize,
                            );
                            _dimensions.text = '${_settings.dimensions}';
                            _maxInputTokens.text =
                                '${_settings.maxInputTokens}';
                            _batchSize.text = '${_settings.batchSize}';
                          });
                        },
                      ),
                    ),
                  _field(_dimensions, isZh ? '默认 dimensions' : 'Dimensions'),
                  _field(
                    _maxInputTokens,
                    isZh ? '最大输入 token' : 'Max input tokens',
                  ),
                  _field(_batchSize, isZh ? '批量大小' : 'Batch size'),
                  _field(_timeout, isZh ? '请求超时秒数' : 'Request timeout seconds'),
                ],
              ),
              _section(
                context,
                title: isZh ? '向量库' : 'Vector Store',
                icon: Icons.storage_outlined,
                children: [
                  _readonly(context, 'Type', 'Qdrant'),
                  _field(_qdrantHost, 'Qdrant host'),
                  _field(_qdrantRestPort, 'REST port'),
                  _field(_qdrantGrpcPort, 'gRPC port'),
                  _field(
                    _collectionName,
                    isZh
                        ? 'Collection 名称（留空自动生成）'
                        : 'Collection name (auto when empty)',
                  ),
                  _switch(
                    isZh ? '自动启动 sidecar' : 'Auto-start sidecar',
                    _settings.autoStartSidecar,
                    (value) => setState(
                      () => _settings = _settings.copyWith(
                        autoStartSidecar: value,
                      ),
                    ),
                  ),
                ],
              ),
              _section(
                context,
                title: isZh ? '文档导入与分块' : 'Document Import and Chunking',
                icon: Icons.segment_outlined,
                children: [
                  _readonly(
                    context,
                    isZh ? '支持文件' : 'Supported files',
                    'Markdown, TXT, code, HTML (PDF reserved)',
                  ),
                  _field(
                    _targetTokens,
                    isZh ? 'child target tokens' : 'Child target tokens',
                  ),
                  _field(
                    _hardMaxTokens,
                    isZh ? 'child hard max tokens' : 'Child hard max tokens',
                  ),
                  _field(
                    _overlapTokens,
                    isZh ? 'overlap tokens' : 'Overlap tokens',
                  ),
                  _switch(
                    isZh ? '复制导入文件' : 'Copy imported files',
                    _settings.copyImportedFiles,
                    (value) {
                      setState(
                        () => _settings = _settings.copyWith(
                          copyImportedFiles: value,
                        ),
                      );
                    },
                  ),
                  _switch(
                    isZh ? 'parent-child 检索' : 'Parent-child retrieval',
                    _settings.parentChildEnabled,
                    (value) {
                      setState(
                        () => _settings = _settings.copyWith(
                          parentChildEnabled: value,
                        ),
                      );
                    },
                  ),
                ],
              ),
              _section(
                context,
                title: isZh ? '标签与时间' : 'Tags and Time',
                icon: Icons.sell_outlined,
                children: [
                  _switch(
                    isZh ? '从路径生成标签' : 'Path-derived tags',
                    _settings.autoPathTags,
                    (value) {
                      setState(
                        () =>
                            _settings = _settings.copyWith(autoPathTags: value),
                      );
                    },
                  ),
                  _switch(
                    isZh ? '读取 front matter 标签' : 'Front matter tags',
                    _settings.autoFrontMatterTags,
                    (value) {
                      setState(
                        () => _settings = _settings.copyWith(
                          autoFrontMatterTags: value,
                        ),
                      );
                    },
                  ),
                  _switch(
                    isZh ? '解析自然语言时间' : 'Parse natural language time',
                    _settings.parseNaturalLanguageTime,
                    (value) {
                      setState(
                        () => _settings = _settings.copyWith(
                          parseNaturalLanguageTime: value,
                        ),
                      );
                    },
                  ),
                  _switch(
                    isZh ? '最新/最近 boost' : 'Recency boost',
                    _settings.recencyBoostEnabled,
                    (value) {
                      setState(
                        () => _settings = _settings.copyWith(
                          recencyBoostEnabled: value,
                        ),
                      );
                    },
                  ),
                ],
              ),
              _section(
                context,
                title: isZh ? '检索召回' : 'Retrieval Recall',
                icon: Icons.travel_explore_rounded,
                children: [
                  _field(_topN, 'topN recall'),
                  _field(_topK, 'topK final'),
                  _field(_minSimilarity, isZh ? '最低相似度' : 'Min similarity'),
                  _field(_sourceCap, isZh ? '单来源上限' : 'Source cap'),
                  _field(_vectorWeight, 'vector weight'),
                  _field(_titleWeight, 'title weight'),
                  _field(_tagWeight, 'tag weight'),
                  _field(_timeWeight, 'time weight'),
                ],
              ),
              _section(
                context,
                title: isZh ? '重排与去重' : 'Rerank and Deduplication',
                icon: Icons.filter_alt_outlined,
                children: [
                  _switch('MMR', _settings.mmrEnabled, (value) {
                    setState(
                      () => _settings = _settings.copyWith(mmrEnabled: value),
                    );
                  }),
                  _switch(
                    isZh ? '邻居扩展' : 'Neighbor expansion',
                    _settings.neighborExpansionEnabled,
                    (value) {
                      setState(
                        () => _settings = _settings.copyWith(
                          neighborExpansionEnabled: value,
                        ),
                      );
                    },
                  ),
                  _switch(
                    isZh ? 'Parent 扩展' : 'Parent expansion',
                    _settings.parentExpansionEnabled,
                    (value) {
                      setState(
                        () => _settings = _settings.copyWith(
                          parentExpansionEnabled: value,
                        ),
                      );
                    },
                  ),
                  _switch(
                    isZh ? '云端 rerank' : 'Cloud rerank',
                    _settings.cloudRerankEnabled,
                    (value) {
                      setState(
                        () => _settings = _settings.copyWith(
                          cloudRerankEnabled: value,
                        ),
                      );
                    },
                  ),
                ],
              ),
              _section(
                context,
                title: isZh ? 'Prompt 追加' : 'Prompt Append',
                icon: Icons.post_add_outlined,
                children: [
                  _field(
                    _maxPromptChunks,
                    isZh ? '最多追加 chunk' : 'Max prompt chunks',
                  ),
                  _field(
                    _maxPromptTokens,
                    isZh ? '最大追加 token' : 'Max prompt tokens',
                  ),
                  _switch(
                    isZh ? '包含 score' : 'Include score',
                    _settings.includeScore,
                    (value) {
                      setState(
                        () =>
                            _settings = _settings.copyWith(includeScore: value),
                      );
                    },
                  ),
                  _switch(
                    isZh ? '包含标签' : 'Include tags',
                    _settings.includeTags,
                    (value) {
                      setState(
                        () =>
                            _settings = _settings.copyWith(includeTags: value),
                      );
                    },
                  ),
                  _switch(
                    isZh ? '包含日期' : 'Include date',
                    _settings.includeDate,
                    (value) {
                      setState(
                        () =>
                            _settings = _settings.copyWith(includeDate: value),
                      );
                    },
                  ),
                  _switch(
                    isZh ? '包含 source path' : 'Include source path',
                    _settings.includeSourcePath,
                    (value) {
                      setState(
                        () => _settings = _settings.copyWith(
                          includeSourcePath: value,
                        ),
                      );
                    },
                  ),
                ],
              ),
              _section(
                context,
                title: isZh ? '发送时行为' : 'Send-time Behavior',
                icon: Icons.send_time_extension_outlined,
                children: [
                  _dropdown(
                    label: isZh ? '检索失败策略' : 'Retrieval failure strategy',
                    value: _settings.failureStrategy,
                    values: const ['fail_open', 'fail_closed'],
                    onChanged: (value) {
                      setState(
                        () => _settings = _settings.copyWith(
                          failureStrategy: value,
                        ),
                      );
                    },
                  ),
                  _switch(
                    isZh ? '无命中继续发送' : 'Continue when no hits',
                    _settings.continueWhenNoHits,
                    (value) {
                      setState(
                        () => _settings = _settings.copyWith(
                          continueWhenNoHits: value,
                        ),
                      );
                    },
                  ),
                  _switch(
                    isZh ? '缓存 query embedding' : 'Cache query embedding',
                    _settings.cacheQueryEmbedding,
                    (value) {
                      setState(
                        () => _settings = _settings.copyWith(
                          cacheQueryEmbedding: value,
                        ),
                      );
                    },
                  ),
                ],
              ),
              _section(
                context,
                title: isZh ? '隐私与云端调用' : 'Privacy and Cloud Calls',
                icon: Icons.privacy_tip_outlined,
                children: [
                  Text(
                    isZh
                        ? '云端 embedding 会发送文档 chunk 与用户 query。默认关闭，开启前请确认数据边界。'
                        : 'Cloud embeddings send document chunks and user queries. They are off by default; confirm your data boundary before enabling.',
                  ),
                  _switch(
                    isZh ? '允许发送文档内容' : 'Allow document cloud embedding',
                    _settings.allowDocumentCloudEmbedding,
                    (value) {
                      setState(
                        () => _settings = _settings.copyWith(
                          allowDocumentCloudEmbedding: value,
                        ),
                      );
                    },
                  ),
                  _switch(
                    isZh ? '允许发送用户 query' : 'Allow query cloud embedding',
                    _settings.allowQueryCloudEmbedding,
                    (value) {
                      setState(
                        () => _settings = _settings.copyWith(
                          allowQueryCloudEmbedding: value,
                        ),
                      );
                    },
                  ),
                  _switch(
                    isZh ? '暴露只读知识库工具' : 'Expose readonly KB tools',
                    _settings.exposeReadonlyTools,
                    (value) {
                      setState(
                        () => _settings = _settings.copyWith(
                          exposeReadonlyTools: value,
                        ),
                      );
                    },
                  ),
                ],
              ),
              _section(
                context,
                title: isZh ? '维护与诊断' : 'Maintenance and Diagnostics',
                icon: Icons.build_circle_outlined,
                children: [
                  _readonly(
                    context,
                    isZh ? 'Collection' : 'Collection',
                    _settings.effectiveCollectionName,
                  ),
                  _readonly(
                    context,
                    isZh ? '距离度量' : 'Distance',
                    _settings.distanceMetric,
                  ),
                  _switch(
                    isZh ? '启用危险管理操作' : 'Enable dangerous admin operations',
                    _settings.enableDangerousAdminOperations,
                    (value) {
                      setState(
                        () => _settings = _settings.copyWith(
                          enableDangerousAdminOperations: value,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(isZh ? '取消' : 'Cancel'),
        ),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save_rounded),
          label: Text(isZh ? '保存' : 'Save'),
        ),
      ],
    );
  }

  Widget _emptyModelState(BuildContext context) {
    final isZh = openHandIsChineseLocale(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isZh
                  ? '没有已开启“嵌入生成”的模型。请先在设置的模型配置中启用该能力。'
                  : 'No model profile has Embedding Generation enabled. Enable it in model settings first.',
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 12, runSpacing: 12, children: children),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController controller, String label) {
    return SizedBox(
      width: 220,
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _readonly(BuildContext context, String label, String value) {
    return SizedBox(
      width: 340,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }

  Widget _switch(String label, bool value, ValueChanged<bool> onChanged) {
    return SizedBox(
      width: 330,
      child: SwitchListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        value: value,
        onChanged: onChanged,
      ),
    );
  }

  Widget _dropdown({
    required String label,
    required String value,
    required List<String> values,
    required ValueChanged<String> onChanged,
  }) {
    return SizedBox(
      width: 260,
      child: DropdownButtonFormField<String>(
        initialValue: values.contains(value) ? value : values.first,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        items: [
          for (final item in values)
            DropdownMenuItem<String>(value: item, child: Text(item)),
        ],
        onChanged: (value) {
          if (value != null) onChanged(value);
        },
      ),
    );
  }
}

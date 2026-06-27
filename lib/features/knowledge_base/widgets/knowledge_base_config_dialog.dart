import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/state/settings_controller.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_model_selector_field.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/util/localized_text.dart';
import '../../ai/index.dart';
import '../../plugin_service/index.dart';
import '../knowledge_base_controller.dart';
import '../model/knowledge_base_settings.dart';
import '../service/knowledge_dependency_service.dart';
import '../service/knowledge_document_parser.dart';
import 'knowledge_dialog_widgets.dart';

Future<void> showKnowledgeBaseConfigDialog(
  BuildContext context, {
  VoidCallback? onOpenPlugins,
}) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => KnowledgeBaseConfigDialog(onOpenPlugins: onOpenPlugins),
  );
}

class KnowledgeBaseConfigDialog extends StatefulWidget {
  const KnowledgeBaseConfigDialog({super.key, this.onOpenPlugins});

  final VoidCallback? onOpenPlugins;

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

  bool _selectedEmbeddingModelAvailable(List<AiModelConfig> models) {
    if (!_settings.hasEmbeddingModel) return false;
    for (final model in models) {
      if (model.id != _settings.providerConfigId) continue;
      return model.allModelIds.contains(_settings.modelId) &&
          model.profileFor(_settings.modelId).supportsEmbeddings;
    }
    return false;
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
    final knowledgeController = context.watch<KnowledgeBaseController>();
    final pluginController = context.watch<PluginServiceController>();
    final settingsController = context.watch<SettingsController>();
    final models = _embeddingModels(settingsController.aiModels);
    final dependencies = knowledgeController.dependencies(pluginController);
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
              ..._buildConfigNotices(
                context,
                dependencies: dependencies,
                embeddingModelAvailable: _selectedEmbeddingModelAvailable(
                  models,
                ),
              ),
              _section(
                context,
                title: isZh ? '嵌入模型' : 'Embedding Model',
                icon: Icons.hub_outlined,
                children: [
                  if (models.isEmpty)
                    _emptyModelState(context)
                  else
                    SizedBox(
                      width: 690,
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
                        modelFilter: (config, modelId) =>
                            config.profileFor(modelId).supportsEmbeddings,
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
                              distanceMetric:
                                  profile.embeddingSimilarityMetric ??
                                  _settings.distanceMetric,
                            );
                            _dimensions.text = '${_settings.dimensions}';
                            _maxInputTokens.text =
                                '${_settings.maxInputTokens}';
                            _batchSize.text = '${_settings.batchSize}';
                          });
                        },
                      ),
                    ),
                  if (_settings.hasEmbeddingModel)
                    _embeddingProfileSummary(context, models),
                  _field(_dimensions, isZh ? '默认向量维度' : 'Default dimensions'),
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
                  _readonly(context, isZh ? '类型' : 'Type', 'Qdrant'),
                  _field(_qdrantHost, isZh ? 'Qdrant 主机' : 'Qdrant host'),
                  _field(_qdrantRestPort, isZh ? 'REST 端口' : 'REST port'),
                  _field(_qdrantGrpcPort, isZh ? 'gRPC 端口' : 'gRPC port'),
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
                    isZh
                        ? KnowledgeDocumentParserRegistry.supportedFilesLabelZh
                        : KnowledgeDocumentParserRegistry.supportedFilesLabelEn,
                  ),
                  _dropdown(
                    label: isZh ? '文档解析引擎' : 'Document parser engine',
                    value: _settings.documentParsingEngine,
                    values: const ['auto'],
                    itemLabel: (value) => switch (value) {
                      'auto' => isZh ? '自动选择' : 'Auto registry',
                      _ => value,
                    },
                    onChanged: (value) {
                      setState(
                        () => _settings = _settings.copyWith(
                          documentParsingEngine: value,
                        ),
                      );
                    },
                  ),
                  _dropdown(
                    label: isZh ? 'Office 解析引擎' : 'Office parser engine',
                    value: _settings.officeParsingEngine,
                    values: const ['open_xml'],
                    itemLabel: (value) => switch (value) {
                      'open_xml' =>
                        isZh ? 'Open XML 内置解析' : 'Built-in Open XML',
                      _ => value,
                    },
                    onChanged: (value) {
                      setState(
                        () => _settings = _settings.copyWith(
                          officeParsingEngine: value,
                        ),
                      );
                    },
                  ),
                  _dropdown(
                    label: isZh ? 'PDF 解析引擎' : 'PDF parser engine',
                    value: _settings.pdfParsingEngine,
                    values: const ['basic_text_stream'],
                    itemLabel: (value) => switch (value) {
                      'basic_text_stream' =>
                        isZh ? '基础文本流解析' : 'Basic text-stream extraction',
                      _ => value,
                    },
                    onChanged: (value) {
                      setState(
                        () => _settings = _settings.copyWith(
                          pdfParsingEngine: value,
                        ),
                      );
                    },
                  ),
                  _dropdown(
                    label: isZh ? 'HTML 解析策略' : 'HTML parsing strategy',
                    value: _settings.htmlParsingMode,
                    values: const ['readable_text', 'plain_text'],
                    itemLabel: (value) => switch (value) {
                      'readable_text' =>
                        isZh ? '结构化可读文本' : 'Readable structure',
                      'plain_text' => isZh ? '纯文本提取' : 'Plain text',
                      _ => value,
                    },
                    onChanged: (value) {
                      setState(
                        () => _settings = _settings.copyWith(
                          htmlParsingMode: value,
                        ),
                      );
                    },
                  ),
                  _dropdown(
                    label: isZh ? '结构化数据策略' : 'Structured data strategy',
                    value: _settings.structuredDataParsingMode,
                    values: const ['readable_markdown', 'raw_fenced'],
                    itemLabel: (value) => switch (value) {
                      'readable_markdown' =>
                        isZh ? '可读 Markdown' : 'Readable Markdown',
                      'raw_fenced' => isZh ? '原文代码块' : 'Raw fenced block',
                      _ => value,
                    },
                    onChanged: (value) {
                      setState(
                        () => _settings = _settings.copyWith(
                          structuredDataParsingMode: value,
                        ),
                      );
                    },
                  ),
                  _dropdown(
                    label: isZh ? '表格解析策略' : 'Table parsing strategy',
                    value: _settings.spreadsheetParsingMode,
                    values: const ['markdown_table', 'row_blocks'],
                    itemLabel: (value) => switch (value) {
                      'markdown_table' =>
                        isZh ? 'Markdown 表格' : 'Markdown table',
                      'row_blocks' => isZh ? '行块文本' : 'Row blocks',
                      _ => value,
                    },
                    onChanged: (value) {
                      setState(
                        () => _settings = _settings.copyWith(
                          spreadsheetParsingMode: value,
                        ),
                      );
                    },
                  ),
                  _dropdown(
                    label: isZh ? '演示文稿策略' : 'Presentation strategy',
                    value: _settings.presentationParsingMode,
                    values: const ['slide_text', 'outline'],
                    itemLabel: (value) => switch (value) {
                      'slide_text' => isZh ? '按幻灯片文本' : 'Slide text',
                      'outline' => isZh ? '大纲文本' : 'Outline',
                      _ => value,
                    },
                    onChanged: (value) {
                      setState(
                        () => _settings = _settings.copyWith(
                          presentationParsingMode: value,
                        ),
                      );
                    },
                  ),
                  _field(
                    _targetTokens,
                    isZh ? '子分块目标 token' : 'Child target tokens',
                  ),
                  _field(
                    _hardMaxTokens,
                    isZh ? '子分块硬上限 token' : 'Child hard max tokens',
                  ),
                  _field(_overlapTokens, isZh ? '重叠 token' : 'Overlap tokens'),
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
                  _field(_topN, isZh ? '召回 topN' : 'topN recall'),
                  _field(_topK, isZh ? '最终 topK' : 'topK final'),
                  _field(_minSimilarity, isZh ? '最低相似度' : 'Min similarity'),
                  _field(_sourceCap, isZh ? '单来源上限' : 'Source cap'),
                  _field(_vectorWeight, isZh ? '向量权重' : 'Vector weight'),
                  _field(_titleWeight, isZh ? '标题权重' : 'Title weight'),
                  _field(_tagWeight, isZh ? '标签权重' : 'Tag weight'),
                  _field(_timeWeight, isZh ? '时间权重' : 'Time weight'),
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
                    isZh ? '父级扩展' : 'Parent expansion',
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
                    isZh ? '包含来源路径' : 'Include source path',
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
                    itemLabel: (value) => switch (value) {
                      'fail_open' => isZh ? '失败后继续发送' : 'Fail open',
                      'fail_closed' => isZh ? '失败后阻止发送' : 'Fail closed',
                      _ => value,
                    },
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
                    isZh ? '缓存查询 embedding' : 'Cache query embedding',
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
                  SizedBox(
                    width: 690,
                    child: KnowledgeDialogNotice(
                      icon: Icons.lock_outline_rounded,
                      message: isZh
                          ? '云端 embedding 会发送文档 chunk 与用户 query。默认关闭，开启前请确认数据边界。'
                          : 'Cloud embeddings send document chunks and user queries. They are off by default; confirm your data boundary before enabling.',
                    ),
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
                    isZh ? '允许发送用户查询' : 'Allow query cloud embedding',
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
        OpenHandDialogActionButton.secondary(
          onPressed: () => Navigator.of(context).pop(),
          label: isZh ? '取消' : 'Cancel',
        ),
        OpenHandDialogActionButton.primary(
          onPressed: _save,
          icon: Icons.save_rounded,
          label: isZh ? '保存' : 'Save',
        ),
      ],
    );
  }

  List<Widget> _buildConfigNotices(
    BuildContext context, {
    required KnowledgeDependencySnapshot dependencies,
    required bool embeddingModelAvailable,
  }) {
    final isZh = openHandIsChineseLocale(context);
    return <Widget>[
      if (!dependencies.ready)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: KnowledgeDialogNotice(
            icon: dependencies.dockerInstalled
                ? Icons.storage_rounded
                : Icons.dns_outlined,
            tone: KnowledgeDialogNoticeTone.warning,
            message: isZh
                ? '知识库依赖未就绪：${dependencies.localizedMessage(true)}'
                : 'Knowledge dependencies are unavailable: ${dependencies.localizedMessage(false)}',
            trailing: widget.onOpenPlugins == null
                ? null
                : KnowledgeDialogNoticeAction(
                    tone: KnowledgeDialogNoticeTone.warning,
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onOpenPlugins?.call();
                    },
                    icon: Icons.power_rounded,
                    label: isZh ? '前往插件' : 'Open Plugins',
                  ),
          ),
        ),
      if (!embeddingModelAvailable)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: KnowledgeDialogNotice(
            icon: Icons.hub_outlined,
            message: isZh
                ? '未配置可用的嵌入模型。请选择已开启“嵌入生成”的模型，并确认隐私开关。'
                : 'No usable embedding model is configured. Choose an embedding-capable model and confirm privacy options.',
          ),
        ),
    ];
  }

  AiModelProfile? _selectedEmbeddingProfile(List<AiModelConfig> models) {
    if (!_settings.hasEmbeddingModel) return null;
    for (final model in models) {
      if (model.id != _settings.providerConfigId) continue;
      if (!model.allModelIds.contains(_settings.modelId)) return null;
      final profile = model.profileFor(_settings.modelId);
      return profile.supportsEmbeddings ? profile : null;
    }
    return null;
  }

  String _listLabel(List<String> values) {
    return values.isEmpty ? '-' : values.join(', ');
  }

  String _nullableBoolLabel(BuildContext context, bool? value) {
    final isZh = openHandIsChineseLocale(context);
    return switch (value) {
      true => isZh ? '是' : 'Yes',
      false => isZh ? '否' : 'No',
      null => isZh ? '未知' : 'Unknown',
    };
  }

  Widget _embeddingProfileSummary(
    BuildContext context,
    List<AiModelConfig> models,
  ) {
    final profile = _selectedEmbeddingProfile(models);
    if (profile == null) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isZh = openHandIsChineseLocale(context);
    final dimensions = <String>[
      '${profile.embeddingDimensions ?? '-'}',
      if (profile.embeddingMinDimensions != null ||
          profile.embeddingMaxDimensions != null)
        '(${profile.embeddingMinDimensions ?? '-'}-${profile.embeddingMaxDimensions ?? '-'})',
    ].join(' ');
    final rows = <(String, String)>[
      (isZh ? '模型' : 'Model', _settings.modelId),
      (
        isZh ? '模型路由' : 'Model Routing',
        _listLabel(<String>[
          if (profile.embeddingQueryModelId != null)
            'query ${profile.embeddingQueryModelId}',
          if (profile.embeddingDocumentModelId != null)
            'doc ${profile.embeddingDocumentModelId}',
        ]),
      ),
      (isZh ? '维度/范围' : 'Dimensions / Range', dimensions),
      (
        isZh ? '最大输入 token' : 'Max Input Tokens',
        '${profile.embeddingMaxInputTokens ?? '-'}',
      ),
      (
        isZh ? 'Batch / 上限' : 'Batch / Limits',
        [
          profile.embeddingBatchSize ?? '-',
          profile.embeddingMaxInputsPerBatch == null
              ? null
              : 'inputs ${profile.embeddingMaxInputsPerBatch}',
          profile.embeddingMaxTokensPerBatch == null
              ? null
              : 'tokens ${profile.embeddingMaxTokensPerBatch}',
        ].whereType<Object>().join(' / '),
      ),
      (
        isZh ? '支持参数' : 'Supported Parameters',
        _listLabel(profile.supportedParameters),
      ),
      (
        isZh ? '输入类型' : 'Input Types',
        [
          _listLabel(profile.embeddingInputTypes),
          if (profile.embeddingDefaultInputType != null)
            '${isZh ? '默认' : 'default'} ${profile.embeddingDefaultInputType}',
          if (profile.embeddingQueryInputType != null)
            'query ${profile.embeddingQueryInputType}',
          if (profile.embeddingDocumentInputType != null)
            'doc ${profile.embeddingDocumentInputType}',
        ].join(' / '),
      ),
      (
        isZh ? '任务类型' : 'Task Types',
        [
          _listLabel(profile.embeddingSupportedTaskTypes),
          if (profile.embeddingDefaultQueryTaskType != null)
            'query ${profile.embeddingDefaultQueryTaskType}',
          if (profile.embeddingDefaultDocumentTaskType != null)
            'doc ${profile.embeddingDefaultDocumentTaskType}',
          if (profile.embeddingDefaultTaskType != null)
            '${isZh ? '默认' : 'default'} ${profile.embeddingDefaultTaskType}',
        ].join(' / '),
      ),
      (
        isZh ? '文本前缀' : 'Text Prefixes',
        _listLabel(<String>[
          if (profile.embeddingQueryTextPrefix != null)
            'query ${profile.embeddingQueryTextPrefix}',
          if (profile.embeddingDocumentTextPrefix != null)
            'doc ${profile.embeddingDocumentTextPrefix}',
        ]),
      ),
      (
        isZh ? '编码格式' : 'Encoding Formats',
        [
          _listLabel(profile.embeddingEncodingFormats),
          if (profile.embeddingDefaultEncodingFormat != null)
            '${isZh ? '默认' : 'default'} ${profile.embeddingDefaultEncodingFormat}',
        ].join(' / '),
      ),
      (
        isZh ? '输出 dtype' : 'Output DType',
        [
          _listLabel(profile.embeddingOutputDTypes),
          if (profile.embeddingDefaultOutputDType != null)
            '${isZh ? '默认' : 'default'} ${profile.embeddingDefaultOutputDType}',
        ].join(' / '),
      ),
      (
        isZh ? '距离/归一化' : 'Metric / Normalized',
        [
          '${profile.embeddingSimilarityMetric ?? '-'} / '
              '${_nullableBoolLabel(context, profile.embeddingOutputsNormalized)}',
          if (profile.embeddingDefaultTruncation != null)
            '${isZh ? '截断' : 'truncate'} ${profile.embeddingDefaultTruncation}',
        ].join(' / '),
      ),
    ];

    return SizedBox(
      width: 690,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.36),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.72),
          ),
        ),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final row in rows)
              Container(
                constraints: const BoxConstraints(minWidth: 190, maxWidth: 318),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.surface.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.48),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      row.$1,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      row.$2.isEmpty ? '-' : row.$2,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _emptyModelState(BuildContext context) {
    final isZh = openHandIsChineseLocale(context);
    return SizedBox(
      width: 690,
      child: KnowledgeDialogNotice(
        icon: Icons.info_outline_rounded,
        message: isZh
            ? '没有已开启“嵌入生成”的模型。请先在设置的模型配置中启用该能力。'
            : 'No model profile has Embedding Generation enabled. Enable it in model settings first.',
      ),
    );
  }

  Widget _section(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return KnowledgeDialogSection(
      title: title,
      icon: icon,
      child: Wrap(spacing: 12, runSpacing: 12, children: children),
    );
  }

  Widget _field(TextEditingController controller, String label) {
    return SizedBox(
      width: kKnowledgeDialogFieldWidth,
      child: TextField(
        controller: controller,
        style: Theme.of(context).textTheme.bodyMedium,
        decoration: knowledgeDialogInputDecoration(context, label),
      ),
    );
  }

  Widget _readonly(BuildContext context, String label, String value) {
    return SizedBox(
      width: kKnowledgeDialogWideFieldWidth,
      child: InputDecorator(
        decoration: knowledgeDialogInputDecoration(context, label),
        child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }

  Widget _switch(String label, bool value, ValueChanged<bool> onChanged) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      width: kKnowledgeDialogWideFieldWidth,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.72),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Switch(
            value: value,
            onChanged: onChanged,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }

  Widget _dropdown({
    required String label,
    required String value,
    required List<String> values,
    required ValueChanged<String> onChanged,
    String Function(String value)? itemLabel,
  }) {
    return SizedBox(
      width: kKnowledgeDialogWideFieldWidth,
      child: DropdownButtonFormField<String>(
        initialValue: values.contains(value) ? value : values.first,
        decoration: knowledgeDialogInputDecoration(context, label),
        items: [
          for (final item in values)
            DropdownMenuItem<String>(
              value: item,
              child: Text(itemLabel?.call(item) ?? item),
            ),
        ],
        onChanged: (value) {
          if (value != null) onChanged(value);
        },
      ),
    );
  }
}

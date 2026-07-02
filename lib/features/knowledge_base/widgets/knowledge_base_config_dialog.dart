import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/state/settings_controller.dart';
import '../../../app/support/silent_log.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/motion_preference.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_model_selector_field.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/localized_text.dart';
import '../../../shared/util/reader_file_type.dart';
import '../../ai/index.dart';
import '../../plugin_service/index.dart';
import '../knowledge_base_controller.dart';
import '../model/knowledge_base_settings.dart';
import '../service/knowledge_dependency_service.dart';
import '../service/knowledge_document_parser.dart';
import 'knowledge_dialog_widgets.dart';

const List<String> _knowledgeChunkStrategies = KnowledgeChunkStrategy.values;

const List<String> _knowledgeDocumentTimeSources = <String>[
  'front_matter',
  'file_modified_at',
  'imported_at',
];

const double _knowledgeConfigItemHeight = 64;
const double _knowledgeConfigGridSpacing = 12;
const double _knowledgeConfigSummaryItemHeight = 76;
const double _knowledgeConfigMinItemWidth = 280;
const double _knowledgeConfigFallbackFullRowWidth =
    _knowledgeConfigMinItemWidth * 2 + _knowledgeConfigGridSpacing;
const double _knowledgeEmbeddingPanelSpacing = 12;
const double _knowledgeEmbeddingSelectorAsideWidth = 226;
const double _knowledgeEmbeddingMetricMinWidth = 148;
const double _knowledgeEmbeddingDetailMinWidth = 258;
const double _knowledgeEmbeddingGroupMinWidth = 300;
const double _knowledgeEmbeddingSettingMinWidth = 176;
const List<String> _knowledgeDependencyPluginIds = <String>['docker', 'qdrant'];

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
  late final TextEditingController _retryCount;
  late final TextEditingController _retryBackoffMs;
  late final TextEditingController _concurrentRequests;
  late final TextEditingController _qdrantHost;
  late final TextEditingController _qdrantRestPort;
  late final TextEditingController _qdrantGrpcPort;
  late final TextEditingController _collectionName;
  late final TextEditingController _hnswM;
  late final TextEditingController _hnswEfConstruct;
  late final TextEditingController _searchEf;
  late final TextEditingController _targetTokens;
  late final TextEditingController _hardMaxTokens;
  late final TextEditingController _overlapTokens;
  late final TextEditingController _maxFileSizeMb;
  late final TextEditingController _topN;
  late final TextEditingController _topK;
  late final TextEditingController _minSimilarity;
  late final TextEditingController _sourceCap;
  late final TextEditingController _vectorWeight;
  late final TextEditingController _titleWeight;
  late final TextEditingController _tagWeight;
  late final TextEditingController _timeWeight;
  late final TextEditingController _exactPhraseWeight;
  late final TextEditingController _sourceQualityWeight;
  late final TextEditingController _mmrLambda;
  late final TextEditingController _maxChunksPerSource;
  late final TextEditingController _rerankTopN;
  late final TextEditingController _rerankTimeout;
  late final TextEditingController _maxPromptChunks;
  late final TextEditingController _maxPromptTokens;
  late final TextEditingController _qdrantMetricsRefreshSeconds;
  late final TextEditingController _qdrantLogRetainLines;
  Future<void>? _dependencyRefreshFuture;

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
    _retryCount = TextEditingController(text: '${_settings.retryCount}');
    _retryBackoffMs = TextEditingController(
      text: '${_settings.retryBackoffMs}',
    );
    _concurrentRequests = TextEditingController(
      text: '${_settings.concurrentRequests}',
    );
    _qdrantHost = TextEditingController(text: _settings.qdrantHost);
    _qdrantRestPort = TextEditingController(
      text: '${_settings.qdrantRestPort}',
    );
    _qdrantGrpcPort = TextEditingController(
      text: '${_settings.qdrantGrpcPort}',
    );
    _collectionName = TextEditingController(text: _settings.collectionName);
    _hnswM = TextEditingController(text: '${_settings.hnswM}');
    _hnswEfConstruct = TextEditingController(
      text: '${_settings.hnswEfConstruct}',
    );
    _searchEf = TextEditingController(text: '${_settings.searchEf}');
    _targetTokens = TextEditingController(text: '${_settings.targetTokens}');
    _hardMaxTokens = TextEditingController(text: '${_settings.hardMaxTokens}');
    _overlapTokens = TextEditingController(text: '${_settings.overlapTokens}');
    _maxFileSizeMb = TextEditingController(text: '${_settings.maxFileSizeMb}');
    _topN = TextEditingController(text: '${_settings.topN}');
    _topK = TextEditingController(text: '${_settings.topK}');
    _minSimilarity = TextEditingController(text: '${_settings.minSimilarity}');
    _sourceCap = TextEditingController(text: '${_settings.sourceCap}');
    _vectorWeight = TextEditingController(text: '${_settings.vectorWeight}');
    _titleWeight = TextEditingController(text: '${_settings.titleWeight}');
    _tagWeight = TextEditingController(text: '${_settings.tagWeight}');
    _timeWeight = TextEditingController(text: '${_settings.timeWeight}');
    _exactPhraseWeight = TextEditingController(
      text: '${_settings.exactPhraseWeight}',
    );
    _sourceQualityWeight = TextEditingController(
      text: '${_settings.sourceQualityWeight}',
    );
    _mmrLambda = TextEditingController(text: '${_settings.mmrLambda}');
    _maxChunksPerSource = TextEditingController(
      text: '${_settings.maxChunksPerSource}',
    );
    _rerankTopN = TextEditingController(text: '${_settings.rerankTopN}');
    _rerankTimeout = TextEditingController(
      text: '${_settings.rerankTimeoutSeconds}',
    );
    _maxPromptChunks = TextEditingController(
      text: '${_settings.maxPromptChunks}',
    );
    _maxPromptTokens = TextEditingController(
      text: '${_settings.maxPromptTokens}',
    );
    _qdrantMetricsRefreshSeconds = TextEditingController(
      text: '${_settings.qdrantMetricsRefreshSeconds}',
    );
    _qdrantLogRetainLines = TextEditingController(
      text: '${_settings.qdrantLogRetainLines}',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_refreshDependencyStatus());
      }
    });
  }

  @override
  void dispose() {
    for (final controller in <TextEditingController>[
      _dimensions,
      _maxInputTokens,
      _batchSize,
      _timeout,
      _retryCount,
      _retryBackoffMs,
      _concurrentRequests,
      _qdrantHost,
      _qdrantRestPort,
      _qdrantGrpcPort,
      _collectionName,
      _hnswM,
      _hnswEfConstruct,
      _searchEf,
      _targetTokens,
      _hardMaxTokens,
      _overlapTokens,
      _maxFileSizeMb,
      _topN,
      _topK,
      _minSimilarity,
      _sourceCap,
      _vectorWeight,
      _titleWeight,
      _tagWeight,
      _timeWeight,
      _exactPhraseWeight,
      _sourceQualityWeight,
      _mmrLambda,
      _maxChunksPerSource,
      _rerankTopN,
      _rerankTimeout,
      _maxPromptChunks,
      _maxPromptTokens,
      _qdrantMetricsRefreshSeconds,
      _qdrantLogRetainLines,
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

  List<AiModelConfig> _rerankModels(List<AiModelConfig> models) {
    final filtered = <AiModelConfig>[];
    for (final model in models) {
      final ids = model.allModelIds
          .where((id) => model.profileFor(id).supportsRerank)
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

  List<AiModelConfig> _readerModels(
    List<AiModelConfig> models, {
    String? sourceType,
  }) {
    final filtered = <AiModelConfig>[];
    final normalizedSource = sourceType == null
        ? null
        : ReaderFileType.normalize(sourceType);
    for (final model in models) {
      final ids = model.allModelIds
          .where((id) {
            final profile = model.profileFor(id);
            return profile.supportsReaderConversion &&
                (normalizedSource == null ||
                    profile.supportsReaderSourceType(normalizedSource));
          })
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

  bool _selectedRerankModelAvailable(List<AiModelConfig> models) {
    if (!_settings.hasRerankModel) return false;
    for (final model in models) {
      if (model.id != _settings.rerankProviderConfigId) continue;
      return model.allModelIds.contains(_settings.rerankModelId) &&
          model.profileFor(_settings.rerankModelId).supportsRerank;
    }
    return false;
  }

  Future<void> _refreshDependencyStatus() {
    final active = _dependencyRefreshFuture;
    if (active != null) return active;
    final pluginController = context.read<PluginServiceController>();
    late final Future<void> refresh;
    refresh = _refreshDependencyStatusUncached(pluginController).whenComplete(
      () {
        if (!mounted || !identical(_dependencyRefreshFuture, refresh)) return;
        setState(() {
          _dependencyRefreshFuture = null;
        });
      },
    );
    setState(() {
      _dependencyRefreshFuture = refresh;
    });
    return refresh;
  }

  Future<void> _refreshDependencyStatusUncached(
    PluginServiceController pluginController,
  ) async {
    try {
      final missingKnownPlugin =
          pluginController.plugins.isEmpty ||
          _knowledgeDependencyPluginIds.any(
            (id) => pluginController.pluginById(id) == null,
          );
      if (missingKnownPlugin) {
        await pluginController.rescan();
        return;
      }
      for (final pluginId in _knowledgeDependencyPluginIds) {
        await pluginController.checkPluginUpdate(pluginId);
      }
    } catch (error, stack) {
      silentLog(
        'knowledge_base_config_dialog',
        'refresh dependency status',
        error,
        stack,
      );
    }
  }

  AiModelProfile? _selectedReaderProfile({
    required List<AiModelConfig> models,
    required KnowledgeReaderParserRule rule,
    required String sourceType,
  }) {
    if (!rule.hasModel) return null;
    final normalizedSource = ReaderFileType.normalize(sourceType);
    for (final model in models) {
      if (model.id != rule.providerConfigId ||
          !model.allModelIds.contains(rule.modelId)) {
        continue;
      }
      final profile = model.profileFor(rule.modelId);
      if (!profile.supportsReaderSourceType(normalizedSource)) return null;
      return profile;
    }
    return null;
  }

  void _updateReaderRule(String sourceType, KnowledgeReaderParserRule rule) {
    final normalizedSource = ReaderFileType.normalize(sourceType);
    final rules = Map<String, KnowledgeReaderParserRule>.of(
      _settings.readerParserRules,
    );
    if (rule.mode == KnowledgeReaderParserMode.local &&
        !rule.hasModel &&
        rule.targetType == ReaderFileType.markdown) {
      rules.remove(normalizedSource);
    } else {
      rules[normalizedSource] = rule;
    }
    setState(() {
      _settings = _settings.copyWith(readerParserRules: rules);
    });
  }

  int _int(TextEditingController controller, int fallback) {
    return positiveIntFromText(controller.text, fallback: fallback);
  }

  int _nonNegativeInt(TextEditingController controller, int fallback) {
    return nonNegativeIntFromText(controller.text, fallback: fallback);
  }

  double _double(TextEditingController controller, double fallback) {
    return doubleFromValue(controller.text, fallback: fallback);
  }

  Future<void> _save() async {
    final settingsController = context.read<SettingsController>();
    final knowledgeController = context.read<KnowledgeBaseController>();
    final next = _settings.copyWith(
      dimensions: _int(_dimensions, _settings.dimensions),
      maxInputTokens: _int(_maxInputTokens, _settings.maxInputTokens),
      batchSize: _int(_batchSize, _settings.batchSize),
      requestTimeoutSeconds: _int(_timeout, _settings.requestTimeoutSeconds),
      retryCount: _nonNegativeInt(_retryCount, _settings.retryCount),
      retryBackoffMs: _int(_retryBackoffMs, _settings.retryBackoffMs),
      concurrentRequests: _int(
        _concurrentRequests,
        _settings.concurrentRequests,
      ),
      qdrantHost: _qdrantHost.text.trim().isEmpty
          ? _settings.qdrantHost
          : _qdrantHost.text.trim(),
      qdrantRestPort: _int(_qdrantRestPort, _settings.qdrantRestPort),
      qdrantGrpcPort: _int(_qdrantGrpcPort, _settings.qdrantGrpcPort),
      collectionName: _collectionName.text.trim(),
      hnswM: _int(_hnswM, _settings.hnswM),
      hnswEfConstruct: _int(_hnswEfConstruct, _settings.hnswEfConstruct),
      searchEf: _int(_searchEf, _settings.searchEf),
      targetTokens: _int(_targetTokens, _settings.targetTokens),
      hardMaxTokens: _int(_hardMaxTokens, _settings.hardMaxTokens),
      overlapTokens: _nonNegativeInt(_overlapTokens, _settings.overlapTokens),
      maxFileSizeMb: _int(_maxFileSizeMb, _settings.maxFileSizeMb),
      topN: _int(_topN, _settings.topN),
      topK: _int(_topK, _settings.topK),
      minSimilarity: _double(_minSimilarity, _settings.minSimilarity),
      sourceCap: _int(_sourceCap, _settings.sourceCap),
      vectorWeight: _double(_vectorWeight, _settings.vectorWeight),
      titleWeight: _double(_titleWeight, _settings.titleWeight),
      tagWeight: _double(_tagWeight, _settings.tagWeight),
      timeWeight: _double(_timeWeight, _settings.timeWeight),
      exactPhraseWeight: _double(
        _exactPhraseWeight,
        _settings.exactPhraseWeight,
      ),
      sourceQualityWeight: _double(
        _sourceQualityWeight,
        _settings.sourceQualityWeight,
      ),
      mmrLambda: _double(_mmrLambda, _settings.mmrLambda),
      maxChunksPerSource: _int(
        _maxChunksPerSource,
        _settings.maxChunksPerSource,
      ),
      rerankTopN: _int(_rerankTopN, _settings.rerankTopN),
      rerankTimeoutSeconds: _int(
        _rerankTimeout,
        _settings.rerankTimeoutSeconds,
      ),
      maxPromptChunks: _int(_maxPromptChunks, _settings.maxPromptChunks),
      maxPromptTokens: _int(_maxPromptTokens, _settings.maxPromptTokens),
      qdrantMetricsRefreshSeconds: _int(
        _qdrantMetricsRefreshSeconds,
        _settings.qdrantMetricsRefreshSeconds,
      ),
      qdrantLogRetainLines: _int(
        _qdrantLogRetainLines,
        _settings.qdrantLogRetainLines,
      ),
      exposeReadonlyTools: settingsController.knowledgeBuiltinToolsEnabled,
    );
    await settingsController.setKnowledgeBuiltinToolsEnabled(
      next.exposeReadonlyTools,
    );
    await knowledgeController.updateSettings(next);
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
    final embeddingModels = _embeddingModels(settingsController.aiModels);
    final rerankModels = _rerankModels(settingsController.aiModels);
    final readerModels = _readerModels(settingsController.aiModels);
    final dependencies = knowledgeController.dependencies(pluginController);
    final dependencyRefreshing =
        _dependencyRefreshFuture != null ||
        _knowledgeDependencyPluginIds.contains(
          pluginController.checkingPluginId,
        );
    final isZh = openHandIsChineseLocale(context);
    final knowledgeBuiltinToolsEnabled =
        settingsController.knowledgeBuiltinToolsEnabled;
    final embeddingModelSupportsRerank =
        _selectedEmbeddingProfile(embeddingModels)?.supportsRerank == true;
    final skipModelRerankEffective =
        _settings.rerankMode == KnowledgeRerankMode.model &&
        _settings.skipModelRerankWhenEmbeddingSupportsRerank &&
        embeddingModelSupportsRerank;
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
                dependencyRefreshing: dependencyRefreshing,
                embeddingModelAvailable: _selectedEmbeddingModelAvailable(
                  embeddingModels,
                ),
              ),
              _section(
                context,
                title: isZh ? '嵌入模型' : 'Embedding Model',
                icon: Icons.hub_outlined,
                subtitle: isZh
                    ? '选择具备嵌入生成能力的模型，并统一调整向量输出、请求韧性与缓存策略。'
                    : 'Choose an embedding-capable model and tune vector output, request resilience, and caching together.',
                children: _embeddingModelSectionChildren(
                  context: context,
                  embeddingModels: embeddingModels,
                  settingsController: settingsController,
                ),
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
                  _dropdown(
                    label: isZh ? '距离度量' : 'Distance metric',
                    value: _settings.distanceMetric,
                    values: KnowledgeDistanceMetric.values,
                    itemLabel: (value) => switch (value) {
                      KnowledgeDistanceMetric.cosine => 'Cosine',
                      KnowledgeDistanceMetric.dot => 'Dot',
                      KnowledgeDistanceMetric.euclidean => 'Euclidean',
                      _ => value,
                    },
                    onChanged: (value) {
                      setState(
                        () => _settings = _settings.copyWith(
                          distanceMetric: value,
                        ),
                      );
                    },
                  ),
                  _field(_hnswM, isZh ? 'HNSW M' : 'HNSW M'),
                  _field(
                    _hnswEfConstruct,
                    isZh ? 'HNSW ef_construct' : 'HNSW ef_construct',
                  ),
                  _field(_searchEf, isZh ? '搜索 hnsw_ef' : 'Search hnsw_ef'),
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
                subtitle: isZh
                    ? '支持 ${KnowledgeDocumentParserRegistry.supportedFilesLabelZh}'
                    : 'Supports ${KnowledgeDocumentParserRegistry.supportedFilesLabelEn}',
                children: [
                  _dropdown(
                    label: isZh ? '分块策略' : 'Chunk strategy',
                    value: _settings.chunkStrategy,
                    values: _knowledgeChunkStrategies,
                    itemLabel: (value) => switch (value) {
                      KnowledgeChunkStrategy.markdownHeadingRecursive =>
                        isZh
                            ? 'Markdown 标题递归窗口'
                            : 'Markdown heading recursive windows',
                      KnowledgeChunkStrategy.paragraphWindow =>
                        isZh ? '段落窗口' : 'Paragraph windows',
                      KnowledgeChunkStrategy.fixedTokenWindow =>
                        isZh ? '固定 token 窗口' : 'Fixed token windows',
                      KnowledgeChunkStrategy.semanticLight =>
                        isZh ? '轻量语义边界' : 'Light semantic boundaries',
                      _ => value,
                    },
                    onChanged: (value) {
                      setState(
                        () => _settings = _settings.copyWith(
                          chunkStrategy: value,
                        ),
                      );
                    },
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
                  _fullRow(
                    _readerParserRulesPanel(
                      context: context,
                      settingsController: settingsController,
                      readerModels: readerModels,
                    ),
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
                  _field(_maxFileSizeMb, isZh ? '单文件 MB 上限' : 'Max file MB'),
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
                    isZh ? '监听原始文件' : 'Watch original files',
                    _settings.watchOriginalFiles,
                    (value) {
                      setState(
                        () => _settings = _settings.copyWith(
                          watchOriginalFiles: value,
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
                    isZh ? '自动标签建议' : 'Auto tag suggestions',
                    _settings.autoTagSuggestions,
                    (value) {
                      setState(
                        () => _settings = _settings.copyWith(
                          autoTagSuggestions: value,
                        ),
                      );
                    },
                  ),
                  _dropdown(
                    label: isZh ? '文档时间来源' : 'Document time source',
                    value: _settings.defaultDocumentTimeSource,
                    values: _knowledgeDocumentTimeSources,
                    itemLabel: (value) => switch (value) {
                      'front_matter' => isZh ? 'Front matter' : 'Front matter',
                      'file_modified_at' =>
                        isZh ? '文件修改时间' : 'File modified time',
                      'imported_at' => isZh ? '导入时间' : 'Imported time',
                      _ => value,
                    },
                    onChanged: (value) {
                      setState(
                        () => _settings = _settings.copyWith(
                          defaultDocumentTimeSource: value,
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
                  _dropdown(
                    label: isZh ? '标签过滤模式' : 'Tag filter mode',
                    value: _settings.tagFilterMode,
                    values: KnowledgeTagFilterMode.values,
                    itemLabel: (value) => switch (value) {
                      KnowledgeTagFilterMode.any => isZh ? '任一标签命中' : 'Any tag',
                      KnowledgeTagFilterMode.all =>
                        isZh ? '全部标签命中' : 'All tags',
                      _ => value,
                    },
                    onChanged: (value) {
                      setState(
                        () => _settings = _settings.copyWith(
                          tagFilterMode: value,
                        ),
                      );
                    },
                  ),
                  _dropdown(
                    label: isZh ? '日期过滤模式' : 'Date filter mode',
                    value: _settings.dateFilterMode,
                    values: KnowledgeDateFilterMode.values,
                    itemLabel: (value) => switch (value) {
                      KnowledgeDateFilterMode.hardWhenExplicit =>
                        isZh ? '显式时间硬过滤' : 'Hard when explicit',
                      KnowledgeDateFilterMode.softBoost =>
                        isZh ? '软加权' : 'Soft boost',
                      KnowledgeDateFilterMode.off => isZh ? '关闭' : 'Off',
                      _ => value,
                    },
                    onChanged: (value) {
                      setState(
                        () => _settings = _settings.copyWith(
                          dateFilterMode: value,
                        ),
                      );
                    },
                  ),
                  _field(_vectorWeight, isZh ? '向量权重' : 'Vector weight'),
                  _field(_titleWeight, isZh ? '标题权重' : 'Title weight'),
                  _field(_tagWeight, isZh ? '标签权重' : 'Tag weight'),
                  _field(_timeWeight, isZh ? '时间权重' : 'Time weight'),
                  _field(
                    _exactPhraseWeight,
                    isZh ? '精确短语权重' : 'Exact phrase weight',
                  ),
                  _field(
                    _sourceQualityWeight,
                    isZh ? '来源质量权重' : 'Source quality weight',
                  ),
                ],
              ),
              _section(
                context,
                title: isZh ? '重排与去重' : 'Rerank and Deduplication',
                icon: Icons.filter_alt_outlined,
                children: [
                  _dropdown(
                    label: isZh ? '重排序方式' : 'Rerank mode',
                    value: _settings.rerankMode,
                    values: KnowledgeRerankMode.values,
                    itemLabel: (value) => switch (value) {
                      KnowledgeRerankMode.off => isZh ? '关闭' : 'Off',
                      KnowledgeRerankMode.localHybrid =>
                        isZh ? '本地混合评分' : 'Local hybrid scoring',
                      KnowledgeRerankMode.mmr =>
                        isZh ? 'MMR 多样性重排' : 'MMR diversity',
                      KnowledgeRerankMode.model =>
                        isZh ? '模型重排序' : 'Model rerank',
                      _ => value,
                    },
                    onChanged: (value) {
                      var next = _settings.copyWith(
                        rerankMode: value,
                        mmrEnabled: value == KnowledgeRerankMode.mmr,
                        cloudRerankEnabled: value == KnowledgeRerankMode.model,
                      );
                      if (value == KnowledgeRerankMode.model &&
                          !_selectedRerankModelAvailable(rerankModels) &&
                          rerankModels.isNotEmpty) {
                        final firstConfig = rerankModels.first;
                        final firstModelId = firstConfig.allModelIds.first;
                        next = next.copyWith(
                          rerankProviderConfigId: firstConfig.id,
                          rerankModelId: firstModelId,
                        );
                      }
                      setState(() => _settings = next);
                    },
                  ),
                  _animatedFullRow(
                    _settings.rerankMode == KnowledgeRerankMode.model
                        ? Column(
                            key: const ValueKey('rerank-model-selector'),
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _switch(
                                isZh
                                    ? '双能力嵌入模型跳过额外重排'
                                    : 'Skip extra rerank for dual-capability embeddings',
                                _settings
                                    .skipModelRerankWhenEmbeddingSupportsRerank,
                                (value) {
                                  setState(
                                    () => _settings = _settings.copyWith(
                                      skipModelRerankWhenEmbeddingSupportsRerank:
                                          value,
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 12),
                              if (skipModelRerankEffective)
                                KnowledgeDialogNotice(
                                  icon: Icons.check_circle_outline_rounded,
                                  message: isZh
                                      ? '当前嵌入模型同时具备“嵌入生成”和“重排序”能力，检索时会直接采用向量召回顺序，不再额外请求重排序模型。'
                                      : 'The current embedding model also supports rerank. Retrieval will use vector recall order without an extra rerank request.',
                                )
                              else if (rerankModels.isEmpty)
                                KnowledgeDialogNotice(
                                  icon: Icons.filter_alt_outlined,
                                  message: isZh
                                      ? '没有已开启“重排序”的模型。请先在设置的模型配置中启用该能力。'
                                      : 'No model profile has Rerank enabled. Enable it in model settings first.',
                                )
                              else ...[
                                if (_settings
                                        .skipModelRerankWhenEmbeddingSupportsRerank &&
                                    !embeddingModelSupportsRerank) ...[
                                  KnowledgeDialogNotice(
                                    icon: Icons.info_outline_rounded,
                                    message: isZh
                                        ? '当前嵌入模型未标记“重排序”能力，仍会请求下方选择的重排序模型。'
                                        : 'The current embedding model is not marked rerank-capable, so the selected rerank model will still be requested.',
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                OpenHandModelSelectorField(
                                  models: rerankModels,
                                  recentSelections:
                                      settingsController.recentModelSelections,
                                  selectedConfigId:
                                      _settings.rerankProviderConfigId,
                                  selectedModelId: _settings.rerankModelId,
                                  required: true,
                                  labelZh: '重排序模型',
                                  labelEn: 'Rerank model',
                                  helperZh: '仅显示已开启“重排序”的模型配置。',
                                  helperEn:
                                      'Only rerank-capable model profiles are shown.',
                                  modelFilter: (config, modelId) =>
                                      config.profileFor(modelId).supportsRerank,
                                  onSelected: (selection) {
                                    setState(() {
                                      _settings = _settings.copyWith(
                                        rerankProviderConfigId: selection.$1,
                                        rerankModelId: selection.$2,
                                      );
                                    });
                                  },
                                ),
                              ],
                            ],
                          )
                        : const SizedBox.shrink(
                            key: ValueKey('rerank-model-selector-empty'),
                          ),
                  ),
                  if (_settings.rerankMode == KnowledgeRerankMode.mmr)
                    _field(_mmrLambda, isZh ? 'MMR lambda' : 'MMR lambda'),
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
                  _field(
                    _maxChunksPerSource,
                    isZh ? '单来源最终 chunk 上限' : 'Max chunks per source',
                  ),
                  if (_settings.rerankMode == KnowledgeRerankMode.model &&
                      !skipModelRerankEffective) ...[
                    _field(_rerankTopN, isZh ? 'Rerank topN' : 'Rerank topN'),
                    _field(
                      _rerankTimeout,
                      isZh ? 'Rerank 超时秒数' : 'Rerank timeout seconds',
                    ),
                  ],
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
                  _switch(
                    isZh ? '包含 chunk ID' : 'Include chunk ID',
                    _settings.includeChunkId,
                    (value) {
                      setState(
                        () => _settings = _settings.copyWith(
                          includeChunkId: value,
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
                    values: KnowledgeFailureStrategy.values,
                    itemLabel: (value) => switch (value) {
                      KnowledgeFailureStrategy.failOpen =>
                        isZh ? '失败后继续发送' : 'Fail open',
                      KnowledgeFailureStrategy.failClosed =>
                        isZh ? '失败后阻止发送' : 'Fail closed',
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
                    isZh ? 'Embedding 失败继续发送' : 'Fail open on embedding error',
                    _settings.embeddingFailureStrategy ==
                        KnowledgeFailureStrategy.failOpen,
                    (value) {
                      setState(
                        () => _settings = _settings.copyWith(
                          embeddingFailureStrategy: value
                              ? KnowledgeFailureStrategy.failOpen
                              : KnowledgeFailureStrategy.failClosed,
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
                    isZh ? '发送前预览' : 'Preview before send',
                    _settings.showPreviewBeforeSend,
                    (value) {
                      setState(
                        () => _settings = _settings.copyWith(
                          showPreviewBeforeSend: value,
                        ),
                      );
                    },
                  ),
                ],
              ),
              _section(
                context,
                title: isZh ? '工具权限' : 'Tool Access',
                icon: Icons.admin_panel_settings_outlined,
                children: [
                  _switch(
                    isZh ? '暴露知识库内建工具' : 'Expose Knowledge Base built-in tools',
                    knowledgeBuiltinToolsEnabled,
                    (value) {
                      setState(
                        () => _settings = _settings.copyWith(
                          exposeReadonlyTools: value,
                        ),
                      );
                      unawaited(
                        settingsController.setKnowledgeBuiltinToolsEnabled(
                          value,
                        ),
                      );
                    },
                    subtitle: isZh
                        ? '开启后 KnowledgeSearch / KnowledgeRead 会直接出现在工具目录，由 AI 自主检索和读取；关闭后两个工具同时禁用。'
                        : 'When enabled, KnowledgeSearch / KnowledgeRead are exposed directly and the AI can decide when to search or read. Disabling turns both tools off.',
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
                  _field(
                    _qdrantMetricsRefreshSeconds,
                    isZh ? 'Qdrant 指标刷新秒数' : 'Qdrant metrics refresh seconds',
                  ),
                  _field(
                    _qdrantLogRetainLines,
                    isZh ? 'Qdrant 日志保留行数' : 'Qdrant log retained lines',
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
    required bool dependencyRefreshing,
    required bool embeddingModelAvailable,
  }) {
    final isZh = openHandIsChineseLocale(context);
    final dependencyMessage = dependencies.localizedMessage(isZh);
    return <Widget>[
      if (!dependencies.ready)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: KnowledgeDialogNotice(
            icon: dependencies.dockerInstalled
                ? Icons.storage_rounded
                : Icons.dns_outlined,
            tone: KnowledgeDialogNoticeTone.warning,
            message: dependencyRefreshing
                ? (isZh
                      ? '正在重新检测 Docker/Qdrant 状态；当前缓存：$dependencyMessage'
                      : 'Refreshing Docker/Qdrant status; cached state: $dependencyMessage')
                : (isZh
                      ? '知识库依赖未就绪：$dependencyMessage'
                      : 'Knowledge dependencies are unavailable: $dependencyMessage'),
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

  String _jsonMapLabel(Map<String, Object?> values) {
    return values.isEmpty ? '-' : jsonEncode(values);
  }

  String _nullableBoolLabel(BuildContext context, bool? value) {
    final isZh = openHandIsChineseLocale(context);
    return switch (value) {
      true => isZh ? '是' : 'Yes',
      false => isZh ? '否' : 'No',
      null => isZh ? '未知' : 'Unknown',
    };
  }

  List<Widget> _embeddingModelSectionChildren({
    required BuildContext context,
    required List<AiModelConfig> embeddingModels,
    required SettingsController settingsController,
  }) {
    return [
      if (embeddingModels.isEmpty)
        _emptyModelState(context)
      else
        _embeddingSelectorPanel(
          embeddingModels: embeddingModels,
          settingsController: settingsController,
        ),
      if (_settings.hasEmbeddingModel)
        _embeddingProfileSummary(context, embeddingModels),
      _embeddingTuningPanel(context),
    ];
  }

  AiModelConfig? _selectedEmbeddingConfig(List<AiModelConfig> models) {
    if (!_settings.hasEmbeddingModel) return null;
    for (final model in models) {
      if (model.id != _settings.providerConfigId) continue;
      if (!model.allModelIds.contains(_settings.modelId)) return null;
      return model;
    }
    return null;
  }

  void _selectEmbeddingModel(
    (String providerConfigId, String modelId) selection,
    List<AiModelConfig> embeddingModels,
  ) {
    AiModelConfig? selectedConfig;
    for (final model in embeddingModels) {
      if (model.id == selection.$1) {
        selectedConfig = model;
        break;
      }
    }
    if (selectedConfig == null ||
        !selectedConfig.allModelIds.contains(selection.$2)) {
      return;
    }
    final profile = selectedConfig.profileFor(selection.$2);
    final next = _settings.copyWith(
      providerConfigId: selection.$1,
      modelId: selection.$2,
      displayName: profile.displayName ?? selection.$2,
      dimensions: profile.embeddingDimensions ?? _settings.dimensions,
      maxInputTokens:
          profile.embeddingMaxInputTokens ?? _settings.maxInputTokens,
      batchSize: profile.embeddingBatchSize ?? _settings.batchSize,
      distanceMetric:
          profile.embeddingSimilarityMetric ?? _settings.distanceMetric,
    );
    setState(() {
      _settings = next;
      _dimensions.text = '${next.dimensions}';
      _maxInputTokens.text = '${next.maxInputTokens}';
      _batchSize.text = '${next.batchSize}';
    });
  }

  Widget _embeddingSelectorPanel({
    required List<AiModelConfig> embeddingModels,
    required SettingsController settingsController,
  }) {
    return _fullRow(
      Builder(
        builder: (context) {
          final colorScheme = Theme.of(context).colorScheme;
          final profile = _selectedEmbeddingProfile(embeddingModels);
          final selectedConfig = _selectedEmbeddingConfig(embeddingModels);
          final duration = openHandMotionDurationMs(context, 180);
          return AnimatedContainer(
            duration: duration,
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                colorScheme.primary.withValues(alpha: 0.045),
                colorScheme.surfaceContainerHighest.withValues(alpha: 0.68),
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color:
                    (profile == null
                            ? colorScheme.outlineVariant
                            : colorScheme.primary)
                        .withValues(alpha: profile == null ? 0.72 : 0.28),
              ),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact =
                    constraints.maxWidth <
                    _knowledgeEmbeddingSelectorAsideWidth + 360;
                final selector = OpenHandModelSelectorField(
                  models: embeddingModels,
                  recentSelections: settingsController.recentModelSelections,
                  selectedConfigId: _settings.providerConfigId,
                  selectedModelId: _settings.modelId,
                  required: true,
                  labelZh: '嵌入模型',
                  labelEn: 'Embedding model',
                  helperZh: '只列出具备嵌入生成能力的模型。切换后会同步模型建议参数。',
                  helperEn:
                      'Only embedding-capable models are shown. Changing model syncs recommended parameters.',
                  modelFilter: (config, modelId) =>
                      config.profileFor(modelId).supportsEmbeddings,
                  onSelected: (selection) =>
                      _selectEmbeddingModel(selection, embeddingModels),
                );
                final status = _embeddingSelectionStatus(
                  context,
                  profile: profile,
                  selectedConfig: selectedConfig,
                );
                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      selector,
                      const SizedBox(height: _knowledgeEmbeddingPanelSpacing),
                      status,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: selector),
                    const SizedBox(width: _knowledgeEmbeddingPanelSpacing),
                    SizedBox(
                      width: _knowledgeEmbeddingSelectorAsideWidth,
                      child: status,
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _embeddingSelectionStatus(
    BuildContext context, {
    required AiModelProfile? profile,
    required AiModelConfig? selectedConfig,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isZh = openHandIsChineseLocale(context);
    final ready = profile != null;
    final foreground = ready
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;
    return AnimatedContainer(
      duration: openHandMotionDurationMs(context, 180),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:
            (ready
                    ? colorScheme.primaryContainer
                    : colorScheme.surfaceContainerHigh)
                .withValues(alpha: ready ? 0.26 : 0.62),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: foreground.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                ready
                    ? Icons.check_circle_outline_rounded
                    : Icons.info_outline_rounded,
                size: 18,
                color: foreground,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  ready
                      ? (isZh ? '模型可用' : 'Model ready')
                      : (isZh ? '等待选择' : 'Pick a model'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            ready
                ? [
                        selectedConfig?.providerLabel,
                        profile.displayName ?? _settings.modelId,
                      ]
                      .whereType<String>()
                      .where((item) => item.trim().isNotEmpty)
                      .join(' / ')
                : (isZh
                      ? '请选择已启用嵌入生成的模型配置。'
                      : 'Choose an embedding-enabled profile.'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: 1.28,
            ),
          ),
          if (ready) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                KnowledgeDialogChip(
                  icon: Icons.straighten_rounded,
                  label:
                      '${profile.embeddingDimensions ?? _settings.dimensions}D',
                ),
                if (profile.supportsRerank)
                  KnowledgeDialogChip(
                    icon: Icons.filter_alt_rounded,
                    label: isZh ? '可重排' : 'Rerank',
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _embeddingProfileSummary(
    BuildContext context,
    List<AiModelConfig> models,
  ) {
    final profile = _selectedEmbeddingProfile(models);
    final isZh = openHandIsChineseLocale(context);
    if (profile == null) {
      return _fullRow(
        KnowledgeDialogNotice(
          icon: Icons.hub_outlined,
          message: isZh
              ? '当前保存的嵌入模型已不可用。请重新选择一个已开启“嵌入生成”的模型。'
              : 'The saved embedding model is unavailable. Choose an embedding-enabled model again.',
        ),
      );
    }
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final selectedConfig = _selectedEmbeddingConfig(models);
    final dimensions = <String>[
      '${profile.embeddingDimensions ?? '-'}',
      if (profile.embeddingMinDimensions != null ||
          profile.embeddingMaxDimensions != null)
        '(${profile.embeddingMinDimensions ?? '-'}-${profile.embeddingMaxDimensions ?? '-'})',
    ].join(' ');
    final metrics = <({IconData icon, String label, String value})>[
      (
        icon: Icons.straighten_rounded,
        label: isZh ? '维度范围' : 'Dimensions',
        value: dimensions,
      ),
      (
        icon: Icons.input_rounded,
        label: isZh ? '最大输入' : 'Max input',
        value: '${profile.embeddingMaxInputTokens ?? '-'}',
      ),
      (
        icon: Icons.batch_prediction_outlined,
        label: isZh ? 'Batch / 上限' : 'Batch / limit',
        value: [
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
        icon: Icons.radar_rounded,
        label: isZh ? '距离/归一化' : 'Metric / normalized',
        value: [
          profile.embeddingSimilarityMetric ?? '-',
          _nullableBoolLabel(context, profile.embeddingOutputsNormalized),
        ].join(' / '),
      ),
    ];
    final details = <({IconData icon, String label, String value})>[
      (
        icon: Icons.route_outlined,
        label: isZh ? '模型路由' : 'Model routing',
        value: _listLabel(<String>[
          if (profile.embeddingQueryModelId != null)
            'query ${profile.embeddingQueryModelId}',
          if (profile.embeddingDocumentModelId != null)
            'doc ${profile.embeddingDocumentModelId}',
        ]),
      ),
      (
        icon: Icons.tune_rounded,
        label: isZh ? '支持参数' : 'Supported parameters',
        value: _listLabel(profile.supportedParameters),
      ),
      (
        icon: Icons.data_object_rounded,
        label: isZh ? '默认参数' : 'Default parameters',
        value: _jsonMapLabel(profile.defaultParameters),
      ),
      (
        icon: Icons.swap_vert_rounded,
        label: isZh ? '输入类型' : 'Input types',
        value: [
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
        icon: Icons.task_alt_rounded,
        label: isZh ? '任务类型' : 'Task types',
        value: [
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
        icon: Icons.short_text_rounded,
        label: isZh ? '文本前缀' : 'Text prefixes',
        value: _listLabel(<String>[
          if (profile.embeddingQueryTextPrefix != null)
            'query ${profile.embeddingQueryTextPrefix}',
          if (profile.embeddingDocumentTextPrefix != null)
            'doc ${profile.embeddingDocumentTextPrefix}',
        ]),
      ),
      (
        icon: Icons.text_fields_rounded,
        label: isZh ? '编码格式' : 'Encoding formats',
        value: [
          _listLabel(profile.embeddingEncodingFormats),
          if (profile.embeddingDefaultEncodingFormat != null)
            '${isZh ? '默认' : 'default'} ${profile.embeddingDefaultEncodingFormat}',
        ].join(' / '),
      ),
      (
        icon: Icons.memory_rounded,
        label: isZh ? '输出 dtype' : 'Output dtype',
        value: [
          _listLabel(profile.embeddingOutputDTypes),
          if (profile.embeddingDefaultOutputDType != null)
            '${isZh ? '默认' : 'default'} ${profile.embeddingDefaultOutputDType}',
          if (profile.embeddingDefaultTruncation != null)
            '${isZh ? '截断' : 'truncate'} ${profile.embeddingDefaultTruncation}',
        ].join(' / '),
      ),
    ];
    return _fullRow(
      AnimatedSize(
        duration: openHandMotionDurationMs(context, 240),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: openHandMotionDurationMs(context, 220),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.985, end: 1).animate(animation),
                alignment: Alignment.topCenter,
                child: child,
              ),
            );
          },
          child: Container(
            key: ValueKey(
              'embedding-profile-${_settings.providerConfigId}-${_settings.modelId}',
            ),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.34,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.62),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer.withValues(
                          alpha: 0.50,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.analytics_outlined,
                        size: 19,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isZh ? '模型画像' : 'Model Profile',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            [selectedConfig?.providerLabel, _settings.modelId]
                                .whereType<String>()
                                .where((item) => item.trim().isNotEmpty)
                                .join(' / '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              height: 1.25,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      alignment: WrapAlignment.end,
                      children: [
                        if (profile.embeddingSupportsCustomDimensions)
                          KnowledgeDialogChip(
                            icon: Icons.open_in_full_rounded,
                            label: isZh ? '可调维度' : 'Custom dims',
                          ),
                        if (profile.supportsRerank)
                          KnowledgeDialogChip(
                            icon: Icons.filter_alt_rounded,
                            label: isZh ? '可重排' : 'Rerank',
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _embeddingMetricsGrid(context, metrics),
                const SizedBox(height: 12),
                _embeddingDetailsGrid(context, details),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _embeddingMetricsGrid(
    BuildContext context,
    List<({IconData icon, String label, String value})> metrics,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : _knowledgeConfigFallbackFullRowWidth;
        final columns =
            maxWidth >=
                _knowledgeEmbeddingMetricMinWidth * 4 +
                    _knowledgeEmbeddingPanelSpacing * 3
            ? 4
            : maxWidth >=
                  _knowledgeEmbeddingMetricMinWidth * 2 +
                      _knowledgeEmbeddingPanelSpacing
            ? 2
            : 1;
        final itemWidth = columns == 1
            ? maxWidth
            : (maxWidth - _knowledgeEmbeddingPanelSpacing * (columns - 1)) /
                  columns;
        return Wrap(
          spacing: _knowledgeEmbeddingPanelSpacing,
          runSpacing: _knowledgeEmbeddingPanelSpacing,
          children: [
            for (final metric in metrics)
              SizedBox(
                width: itemWidth,
                height: _knowledgeConfigSummaryItemHeight,
                child: _embeddingMetricTile(context, metric),
              ),
          ],
        );
      },
    );
  }

  Widget _embeddingMetricTile(
    BuildContext context,
    ({IconData icon, String label, String value}) metric,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.46),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: colorScheme.secondaryContainer.withValues(alpha: 0.48),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              metric.icon,
              size: 17,
              color: colorScheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  metric.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  metric.value.trim().isEmpty ? '-' : metric.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _embeddingDetailsGrid(
    BuildContext context,
    List<({IconData icon, String label, String value})> details,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : _knowledgeConfigFallbackFullRowWidth;
        final columns =
            maxWidth >=
                _knowledgeEmbeddingDetailMinWidth * 2 +
                    _knowledgeEmbeddingPanelSpacing
            ? 2
            : 1;
        final itemWidth = columns == 1
            ? maxWidth
            : (maxWidth - _knowledgeEmbeddingPanelSpacing) / 2;
        return Wrap(
          spacing: _knowledgeEmbeddingPanelSpacing,
          runSpacing: _knowledgeEmbeddingPanelSpacing,
          children: [
            for (final detail in details)
              SizedBox(
                width: itemWidth,
                child: _embeddingDetailTile(context, detail),
              ),
          ],
        );
      },
    );
  }

  Widget _embeddingDetailTile(
    BuildContext context,
    ({IconData icon, String label, String value}) detail,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 58),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.54),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.34),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(detail.icon, size: 17, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  detail.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  detail.value.trim().isEmpty ? '-' : detail.value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface,
                    height: 1.24,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _embeddingTuningPanel(BuildContext context) {
    final isZh = openHandIsChineseLocale(context);
    return _fullRow(
      Builder(
        builder: (context) {
          return LayoutBuilder(
            builder: (context, constraints) {
              final maxWidth = constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : _knowledgeConfigFallbackFullRowWidth;
              final columns =
                  maxWidth >=
                      _knowledgeEmbeddingGroupMinWidth * 2 +
                          _knowledgeEmbeddingPanelSpacing
                  ? 2
                  : 1;
              final groupWidth = columns == 1
                  ? maxWidth
                  : (maxWidth - _knowledgeEmbeddingPanelSpacing) / 2;
              return Wrap(
                spacing: _knowledgeEmbeddingPanelSpacing,
                runSpacing: _knowledgeEmbeddingPanelSpacing,
                children: [
                  _embeddingTuningGroup(
                    context,
                    width: groupWidth,
                    icon: Icons.account_tree_outlined,
                    title: isZh ? '向量输出' : 'Vector Output',
                    subtitle: isZh
                        ? '控制最终写入向量库的维度、输入预算与单批规模。'
                        : 'Controls vector dimensions, input budget, and batch size.',
                    child: _embeddingSettingsGrid(
                      context,
                      children: [
                        _embeddingSettingTextField(
                          context,
                          controller: _dimensions,
                          label: isZh ? '默认向量维度' : 'Default dimensions',
                          icon: Icons.straighten_rounded,
                        ),
                        _embeddingSettingTextField(
                          context,
                          controller: _maxInputTokens,
                          label: isZh ? '最大输入 token' : 'Max input tokens',
                          icon: Icons.input_rounded,
                        ),
                        _embeddingSettingTextField(
                          context,
                          controller: _batchSize,
                          label: isZh ? '批量大小' : 'Batch size',
                          icon: Icons.batch_prediction_outlined,
                        ),
                      ],
                    ),
                  ),
                  _embeddingTuningGroup(
                    context,
                    width: groupWidth,
                    icon: Icons.speed_rounded,
                    title: isZh ? '请求韧性' : 'Request Resilience',
                    subtitle: isZh
                        ? '限制请求耗时、失败重试和并发，避免资源被无限占用。'
                        : 'Bounds timeout, retries, backoff, and concurrency.',
                    child: _embeddingSettingsGrid(
                      context,
                      children: [
                        _embeddingSettingTextField(
                          context,
                          controller: _timeout,
                          label: isZh ? '请求超时' : 'Request timeout',
                          icon: Icons.timer_outlined,
                          suffix: 's',
                        ),
                        _embeddingSettingTextField(
                          context,
                          controller: _retryCount,
                          label: isZh ? '失败重试' : 'Retry count',
                          icon: Icons.replay_rounded,
                        ),
                        _embeddingSettingTextField(
                          context,
                          controller: _retryBackoffMs,
                          label: isZh ? '重试退避' : 'Retry backoff',
                          icon: Icons.more_time_rounded,
                          suffix: 'ms',
                        ),
                        _embeddingSettingTextField(
                          context,
                          controller: _concurrentRequests,
                          label: isZh ? '并发请求' : 'Concurrent requests',
                          icon: Icons.call_split_rounded,
                        ),
                      ],
                    ),
                  ),
                  _embeddingTuningGroup(
                    context,
                    width: maxWidth,
                    icon: Icons.privacy_tip_outlined,
                    title: isZh ? '隐私与缓存' : 'Privacy and Cache',
                    subtitle: isZh
                        ? '云端 embedding 会发送文档 chunk 或用户 query；默认保持关闭。'
                        : 'Cloud embeddings send document chunks or user queries; keep them off unless approved.',
                    child: _embeddingSettingsGrid(
                      context,
                      minItemWidth: 220,
                      children: [
                        _embeddingSwitchTile(
                          context,
                          label: isZh
                              ? '允许发送文档内容'
                              : 'Allow document cloud embedding',
                          subtitle: isZh
                              ? '导入文档向量化时生效'
                              : 'Used while indexing documents',
                          value: _settings.allowDocumentCloudEmbedding,
                          onChanged: (value) {
                            setState(
                              () => _settings = _settings.copyWith(
                                allowDocumentCloudEmbedding: value,
                              ),
                            );
                          },
                        ),
                        _embeddingSwitchTile(
                          context,
                          label: isZh
                              ? '允许发送用户查询'
                              : 'Allow query cloud embedding',
                          subtitle: isZh
                              ? '发送消息检索时生效'
                              : 'Used while retrieving on send',
                          value: _settings.allowQueryCloudEmbedding,
                          onChanged: (value) {
                            setState(
                              () => _settings = _settings.copyWith(
                                allowQueryCloudEmbedding: value,
                              ),
                            );
                          },
                        ),
                        _embeddingSwitchTile(
                          context,
                          label: isZh
                              ? '缓存查询 embedding'
                              : 'Cache query embedding',
                          subtitle: isZh
                              ? '复用重复查询向量'
                              : 'Reuses vectors for repeated queries',
                          value: _settings.cacheQueryEmbedding,
                          onChanged: (value) {
                            setState(
                              () => _settings = _settings.copyWith(
                                cacheQueryEmbedding: value,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _embeddingTuningGroup(
    BuildContext context, {
    required double width,
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.30),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.54),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.80,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 18, color: colorScheme.primary),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.24,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _embeddingSettingsGrid(
    BuildContext context, {
    required List<Widget> children,
    double minItemWidth = _knowledgeEmbeddingSettingMinWidth,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : minItemWidth;
        final columns =
            maxWidth >= minItemWidth * 2 + _knowledgeEmbeddingPanelSpacing
            ? 2
            : 1;
        final itemWidth = columns == 1
            ? maxWidth
            : (maxWidth - _knowledgeEmbeddingPanelSpacing) / 2;
        return Wrap(
          spacing: _knowledgeEmbeddingPanelSpacing,
          runSpacing: _knowledgeEmbeddingPanelSpacing,
          children: [
            for (final child in children)
              SizedBox(width: itemWidth, child: child),
          ],
        );
      },
    );
  }

  Widget _embeddingSettingTextField(
    BuildContext context, {
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? suffix,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
      decoration: knowledgeDialogInputDecoration(context, label).copyWith(
        prefixIcon: Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 38,
          minHeight: 38,
        ),
        suffixText: suffix,
      ),
    );
  }

  Widget _embeddingSwitchTile(
    BuildContext context, {
    required String label,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return AnimatedContainer(
      duration: openHandMotionDurationMs(context, 180),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color:
            (value
                    ? colorScheme.primaryContainer
                    : colorScheme.surfaceContainerHigh)
                .withValues(alpha: value ? 0.24 : 0.58),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (value ? colorScheme.primary : colorScheme.outlineVariant)
              .withValues(alpha: value ? 0.24 : 0.58),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                    height: 1.22,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.22,
                  ),
                ),
              ],
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

  Widget _emptyModelState(BuildContext context) {
    final isZh = openHandIsChineseLocale(context);
    return _fullRow(
      KnowledgeDialogNotice(
        icon: Icons.info_outline_rounded,
        message: isZh
            ? '没有已开启“嵌入生成”的模型。请先在设置的模型配置中启用该能力。'
            : 'No model profile has Embedding Generation enabled. Enable it in model settings first.',
      ),
    );
  }

  Widget _readerParserRulesPanel({
    required BuildContext context,
    required SettingsController settingsController,
    required List<AiModelConfig> readerModels,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isZh = openHandIsChineseLocale(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.72),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_fix_high_rounded,
                size: 18,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isZh ? '模型解析规则' : 'Model Parsing Rules',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            isZh
                ? '为指定源文件类型启用 reader 模型后，导入时会先转换为目标类型，再进入分块与向量化。'
                : 'When a reader model is enabled for a source type, import converts it to the target type before chunking and embedding.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          for (final sourceType in ReaderFileType.sourceTypes) ...[
            _readerParserRuleRow(
              context: context,
              sourceType: sourceType,
              settingsController: settingsController,
              readerModels: _readerModels(
                settingsController.aiModels,
                sourceType: sourceType,
              ),
            ),
            if (sourceType != ReaderFileType.sourceTypes.last)
              const SizedBox(height: 10),
          ],
          if (readerModels.isEmpty) ...[
            const SizedBox(height: 12),
            KnowledgeDialogNotice(
              icon: Icons.info_outline_rounded,
              message: isZh
                  ? '当前没有已开启“读取转换”的模型。请先在设置的模型配置中启用该能力并配置源/目标类型。'
                  : 'No model profile has Read Conversion enabled. Enable it in model settings and configure source/target types first.',
            ),
          ],
        ],
      ),
    );
  }

  Widget _readerParserRuleRow({
    required BuildContext context,
    required String sourceType,
    required SettingsController settingsController,
    required List<AiModelConfig> readerModels,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isZh = openHandIsChineseLocale(context);
    final rule = _settings.readerRuleForSourceType(sourceType);
    final selectedProfile = _selectedReaderProfile(
      models: readerModels,
      rule: rule,
      sourceType: sourceType,
    );
    final targetValues = selectedProfile == null
        ? ReaderFileType.targetTypes
        : selectedProfile.readerTargetTypes
              .where(ReaderFileType.targetTypes.contains)
              .toList(growable: false);
    final safeTargetValues = targetValues.isEmpty
        ? ReaderFileType.targetTypes
        : targetValues;
    final safeTarget = safeTargetValues.contains(rule.targetType)
        ? rule.targetType
        : safeTargetValues.first;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  ReaderFileType.label(sourceType, isZh: isZh),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 150,
                child: DropdownButtonFormField<String>(
                  initialValue: rule.mode,
                  isExpanded: true,
                  decoration: knowledgeDialogInputDecoration(
                    context,
                    isZh ? '解析方式' : 'Parser',
                  ),
                  items: [
                    DropdownMenuItem(
                      value: KnowledgeReaderParserMode.local,
                      child: Text(isZh ? '本地解析' : 'Local'),
                    ),
                    DropdownMenuItem(
                      value: KnowledgeReaderParserMode.model,
                      child: Text(isZh ? '模型解析' : 'Model'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    var next = value == KnowledgeReaderParserMode.local
                        ? const KnowledgeReaderParserRule()
                        : rule.copyWith(mode: value);
                    if (value == KnowledgeReaderParserMode.model &&
                        !rule.hasModel &&
                        readerModels.isNotEmpty) {
                      final config = readerModels.first;
                      final modelId = config.allModelIds.first;
                      final profile = config.profileFor(modelId);
                      final targets = profile.readerTargetTypes
                          .where(ReaderFileType.targetTypes.contains)
                          .toList(growable: false);
                      next = next.copyWith(
                        providerConfigId: config.id,
                        modelId: modelId,
                        targetType: targets.isEmpty
                            ? ReaderFileType.markdown
                            : targets.first,
                      );
                    }
                    _updateReaderRule(sourceType, next);
                  },
                ),
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutBack,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween<double>(
                      begin: 0.98,
                      end: 1,
                    ).animate(animation),
                    alignment: Alignment.topCenter,
                    child: child,
                  ),
                );
              },
              child: rule.mode == KnowledgeReaderParserMode.model
                  ? Padding(
                      key: ValueKey('reader-rule-$sourceType-model'),
                      padding: const EdgeInsets.only(top: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (readerModels.isEmpty)
                            KnowledgeDialogNotice(
                              icon: Icons.info_outline_rounded,
                              message: isZh
                                  ? '没有可读取 ${ReaderFileType.label(sourceType, isZh: isZh)} 的 reader 模型。'
                                  : 'No reader model can read ${ReaderFileType.label(sourceType, isZh: isZh)}.',
                            )
                          else ...[
                            OpenHandModelSelectorField(
                              models: readerModels,
                              recentSelections:
                                  settingsController.recentModelSelections,
                              selectedConfigId: rule.providerConfigId,
                              selectedModelId: rule.modelId,
                              required: true,
                              labelZh: 'Reader 模型',
                              labelEn: 'Reader model',
                              helperZh: '仅显示具备“读取转换”且支持当前源文件类型的模型。',
                              helperEn:
                                  'Only read-conversion models supporting this source type are shown.',
                              modelFilter: (config, modelId) => config
                                  .profileFor(modelId)
                                  .supportsReaderSourceType(sourceType),
                              onSelected: (selection) {
                                final config = readerModels.firstWhere(
                                  (item) => item.id == selection.$1,
                                );
                                final profile = config.profileFor(selection.$2);
                                final targets = profile.readerTargetTypes
                                    .where(ReaderFileType.targetTypes.contains)
                                    .toList(growable: false);
                                final target = targets.contains(rule.targetType)
                                    ? rule.targetType
                                    : (targets.isEmpty
                                          ? ReaderFileType.markdown
                                          : targets.first);
                                _updateReaderRule(
                                  sourceType,
                                  rule.copyWith(
                                    mode: KnowledgeReaderParserMode.model,
                                    providerConfigId: selection.$1,
                                    modelId: selection.$2,
                                    targetType: target,
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 10),
                            DropdownButtonFormField<String>(
                              initialValue: safeTarget,
                              isExpanded: true,
                              decoration: knowledgeDialogInputDecoration(
                                context,
                                isZh ? '转换目标类型' : 'Target type',
                              ),
                              items: [
                                for (final item in safeTargetValues)
                                  DropdownMenuItem(
                                    value: item,
                                    child: Text(
                                      ReaderFileType.label(item, isZh: isZh),
                                    ),
                                  ),
                              ],
                              onChanged: (value) {
                                if (value == null) return;
                                _updateReaderRule(
                                  sourceType,
                                  rule.copyWith(targetType: value),
                                );
                              },
                            ),
                          ],
                        ],
                      ),
                    )
                  : const SizedBox.shrink(key: ValueKey('reader-rule-local')),
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
    String? subtitle,
    required List<Widget> children,
  }) {
    return KnowledgeDialogSection(
      title: title,
      icon: icon,
      subtitle: subtitle,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : _knowledgeConfigFallbackFullRowWidth;
          final columns =
              maxWidth >=
                  _knowledgeConfigMinItemWidth * 2 + _knowledgeConfigGridSpacing
              ? 2
              : 1;
          final itemWidth = columns == 1
              ? maxWidth
              : (maxWidth - _knowledgeConfigGridSpacing) / 2;
          return _KnowledgeConfigGridScope(
            itemWidth: itemWidth,
            fullWidth: maxWidth,
            columns: columns,
            child: Wrap(
              spacing: _knowledgeConfigGridSpacing,
              runSpacing: 12,
              children: children,
            ),
          );
        },
      ),
    );
  }

  Widget _fullRow(Widget child) {
    return Builder(
      builder: (context) {
        final metrics = _KnowledgeConfigGridScope.of(context);
        return SizedBox(width: metrics.fullWidth, child: child);
      },
    );
  }

  Widget _animatedFullRow(Widget child) {
    return _fullRow(
      AnimatedSize(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutBack,
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.98, end: 1).animate(animation),
                alignment: Alignment.topCenter,
                child: child,
              ),
            );
          },
          child: child,
        ),
      ),
    );
  }

  Widget _field(TextEditingController controller, String label) {
    return Builder(
      builder: (context) {
        final metrics = _KnowledgeConfigGridScope.of(context);
        return SizedBox(
          width: metrics.itemWidth,
          height: _knowledgeConfigItemHeight,
          child: TextField(
            controller: controller,
            style: Theme.of(context).textTheme.bodyMedium,
            decoration: knowledgeDialogInputDecoration(context, label),
          ),
        );
      },
    );
  }

  Widget _readonly(BuildContext context, String label, String value) {
    return Builder(
      builder: (context) {
        final metrics = _KnowledgeConfigGridScope.of(context);
        return SizedBox(
          width: metrics.itemWidth,
          height: _knowledgeConfigItemHeight,
          child: InputDecorator(
            decoration: knowledgeDialogInputDecoration(context, label),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
        );
      },
    );
  }

  Widget _switch(
    String label,
    bool value,
    ValueChanged<bool> onChanged, {
    String? subtitle,
  }) {
    return Builder(
      builder: (context) {
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;
        final metrics = _KnowledgeConfigGridScope.of(context);
        return Container(
          width: metrics.itemWidth,
          height: subtitle == null ? _knowledgeConfigItemHeight : 92,
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
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: subtitle == null ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ],
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
      },
    );
  }

  Widget _dropdown({
    required String label,
    required String value,
    required List<String> values,
    required ValueChanged<String> onChanged,
    String Function(String value)? itemLabel,
  }) {
    return Builder(
      builder: (context) {
        final metrics = _KnowledgeConfigGridScope.of(context);
        return SizedBox(
          width: metrics.itemWidth,
          height: _knowledgeConfigItemHeight,
          child: DropdownButtonFormField<String>(
            initialValue: values.contains(value) ? value : values.first,
            isExpanded: true,
            decoration: knowledgeDialogInputDecoration(context, label),
            selectedItemBuilder: (context) => [
              for (final item in values)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    itemLabel?.call(item) ?? item,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            items: [
              for (final item in values)
                DropdownMenuItem<String>(
                  value: item,
                  child: Text(
                    itemLabel?.call(item) ?? item,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) {
              if (value != null) onChanged(value);
            },
          ),
        );
      },
    );
  }
}

class _KnowledgeConfigGridScope extends InheritedWidget {
  const _KnowledgeConfigGridScope({
    required this.itemWidth,
    required this.fullWidth,
    required this.columns,
    required super.child,
  });

  final double itemWidth;
  final double fullWidth;
  final int columns;

  static _KnowledgeConfigGridScope of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<_KnowledgeConfigGridScope>() ??
        const _KnowledgeConfigGridScope(
          itemWidth: _knowledgeConfigMinItemWidth,
          fullWidth: _knowledgeConfigFallbackFullRowWidth,
          columns: 2,
          child: SizedBox.shrink(),
        );
  }

  @override
  bool updateShouldNotify(_KnowledgeConfigGridScope oldWidget) {
    return itemWidth != oldWidget.itemWidth ||
        fullWidth != oldWidget.fullWidth ||
        columns != oldWidget.columns;
  }
}

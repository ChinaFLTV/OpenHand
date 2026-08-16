import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/state/settings_controller.dart';
import '../../../app/support/silent_log.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/net/tcp_port_utils.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/animated_menu.dart';
import '../../../shared/ui/motion_durations.dart';
import '../../../shared/ui/motion_preference.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_model_selector_field.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/localized_text.dart';
import '../../../shared/util/reader_file_type.dart';
import '../../ai/index.dart';
import '../../plugin_service/index.dart';
import '../knowledge_base_controller.dart';
import '../knowledge_base_errors.dart';
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
    builder: (_) => _KnowledgeBaseConfigDialog(onOpenPlugins: onOpenPlugins),
  );
}

class _KnowledgeBaseConfigDialog extends StatefulWidget {
  const _KnowledgeBaseConfigDialog({this.onOpenPlugins});

  final VoidCallback? onOpenPlugins;

  @override
  State<_KnowledgeBaseConfigDialog> createState() =>
      _KnowledgeBaseConfigDialogState();
}

class _KnowledgeBaseConfigDialogState
    extends State<_KnowledgeBaseConfigDialog> {
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
  late bool _knowledgeBuiltinToolsEnabled;
  bool _saving = false;
  Future<void>? _dependencyRefreshFuture;

  @override
  void initState() {
    super.initState();
    _settings = context.read<KnowledgeBaseController>().settings;
    _knowledgeBuiltinToolsEnabled = context
        .read<SettingsController>()
        .knowledgeBuiltinToolsEnabled;
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
      silentLog('knowledge_base_config_dialog', '刷新依赖状态', error, stack);
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

  int _int(
    TextEditingController controller,
    IntValueRange range,
    int fallback,
  ) {
    return range.fromValueOr(controller.text, fallback: fallback);
  }

  int _port(TextEditingController controller, int fallback) {
    return tcpPortFromTextOr(controller.text, fallback: fallback);
  }

  double _double(
    TextEditingController controller,
    DoubleValueRange range,
    double fallback,
  ) {
    return range.fromValueOr(controller.text, fallback: fallback);
  }

  Future<void> _save() async {
    final settingsController = context.read<SettingsController>();
    final knowledgeController = context.read<KnowledgeBaseController>();
    final next = _settings.copyWith(
      dimensions: _int(
        _dimensions,
        KnowledgeBaseSettingRanges.dimensions,
        _settings.dimensions,
      ),
      maxInputTokens: _int(
        _maxInputTokens,
        KnowledgeBaseSettingRanges.maxInputTokens,
        _settings.maxInputTokens,
      ),
      batchSize: _int(
        _batchSize,
        KnowledgeBaseSettingRanges.batchSize,
        _settings.batchSize,
      ),
      requestTimeoutSeconds: _int(
        _timeout,
        KnowledgeBaseSettingRanges.requestTimeoutSeconds,
        _settings.requestTimeoutSeconds,
      ),
      retryCount: _int(
        _retryCount,
        KnowledgeBaseSettingRanges.retryCount,
        _settings.retryCount,
      ),
      retryBackoffMs: _int(
        _retryBackoffMs,
        KnowledgeBaseSettingRanges.retryBackoffMs,
        _settings.retryBackoffMs,
      ),
      concurrentRequests: _int(
        _concurrentRequests,
        KnowledgeBaseSettingRanges.concurrentRequests,
        _settings.concurrentRequests,
      ),
      qdrantHost: KnowledgeBaseSettings.normalizeQdrantHost(
        _qdrantHost.text,
        fallback: _settings.qdrantHost,
      ),
      qdrantRestPort: _port(_qdrantRestPort, _settings.qdrantRestPort),
      qdrantGrpcPort: _port(_qdrantGrpcPort, _settings.qdrantGrpcPort),
      collectionName: _collectionName.text.trim(),
      hnswM: _int(_hnswM, KnowledgeBaseSettingRanges.hnswM, _settings.hnswM),
      hnswEfConstruct: _int(
        _hnswEfConstruct,
        KnowledgeBaseSettingRanges.hnswEfConstruct,
        _settings.hnswEfConstruct,
      ),
      searchEf: _int(
        _searchEf,
        KnowledgeBaseSettingRanges.searchEf,
        _settings.searchEf,
      ),
      targetTokens: _int(
        _targetTokens,
        KnowledgeBaseSettingRanges.targetTokens,
        _settings.targetTokens,
      ),
      hardMaxTokens: _int(
        _hardMaxTokens,
        KnowledgeBaseSettingRanges.hardMaxTokens,
        _settings.hardMaxTokens,
      ),
      overlapTokens: _int(
        _overlapTokens,
        KnowledgeBaseSettingRanges.overlapTokens,
        _settings.overlapTokens,
      ),
      maxFileSizeMb: _int(
        _maxFileSizeMb,
        KnowledgeBaseSettingRanges.maxFileSizeMb,
        _settings.maxFileSizeMb,
      ),
      topN: _int(_topN, KnowledgeBaseSettingRanges.topN, _settings.topN),
      topK: _int(_topK, KnowledgeBaseSettingRanges.topK, _settings.topK),
      minSimilarity: _double(
        _minSimilarity,
        KnowledgeBaseSettingRanges.minSimilarity,
        _settings.minSimilarity,
      ),
      sourceCap: _int(
        _sourceCap,
        KnowledgeBaseSettingRanges.sourceCap,
        _settings.sourceCap,
      ),
      vectorWeight: _double(
        _vectorWeight,
        KnowledgeBaseSettingRanges.vectorWeight,
        _settings.vectorWeight,
      ),
      titleWeight: _double(
        _titleWeight,
        KnowledgeBaseSettingRanges.titleWeight,
        _settings.titleWeight,
      ),
      tagWeight: _double(
        _tagWeight,
        KnowledgeBaseSettingRanges.tagWeight,
        _settings.tagWeight,
      ),
      timeWeight: _double(
        _timeWeight,
        KnowledgeBaseSettingRanges.timeWeight,
        _settings.timeWeight,
      ),
      exactPhraseWeight: _double(
        _exactPhraseWeight,
        KnowledgeBaseSettingRanges.exactPhraseWeight,
        _settings.exactPhraseWeight,
      ),
      sourceQualityWeight: _double(
        _sourceQualityWeight,
        KnowledgeBaseSettingRanges.sourceQualityWeight,
        _settings.sourceQualityWeight,
      ),
      mmrLambda: _double(
        _mmrLambda,
        KnowledgeBaseSettingRanges.mmrLambda,
        _settings.mmrLambda,
      ),
      maxChunksPerSource: _int(
        _maxChunksPerSource,
        KnowledgeBaseSettingRanges.maxChunksPerSource,
        _settings.maxChunksPerSource,
      ),
      rerankTopN: _int(
        _rerankTopN,
        KnowledgeBaseSettingRanges.rerankTopN,
        _settings.rerankTopN,
      ),
      rerankTimeoutSeconds: _int(
        _rerankTimeout,
        KnowledgeBaseSettingRanges.rerankTimeoutSeconds,
        _settings.rerankTimeoutSeconds,
      ),
      maxPromptChunks: _int(
        _maxPromptChunks,
        KnowledgeBaseSettingRanges.maxPromptChunks,
        _settings.maxPromptChunks,
      ),
      maxPromptTokens: _int(
        _maxPromptTokens,
        KnowledgeBaseSettingRanges.maxPromptTokens,
        _settings.maxPromptTokens,
      ),
      qdrantMetricsRefreshSeconds: _int(
        _qdrantMetricsRefreshSeconds,
        KnowledgeBaseSettingRanges.qdrantMetricsRefreshSeconds,
        _settings.qdrantMetricsRefreshSeconds,
      ),
      qdrantLogRetainLines: _int(
        _qdrantLogRetainLines,
        KnowledgeBaseSettingRanges.qdrantLogRetainLines,
        _settings.qdrantLogRetainLines,
      ),
    );
    if (_saving) return;
    setState(() => _saving = true);
    final previousSettings = knowledgeController.settings;
    var knowledgeSettingsSaved = false;
    try {
      await knowledgeController.updateSettings(next);
      knowledgeSettingsSaved = true;
      final toolsSaved = await settingsController
          .setKnowledgeBuiltinToolsEnabled(_knowledgeBuiltinToolsEnabled);
      if (!toolsSaved) {
        throw StateError('知识库工具访问设置保存失败。');
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      showOpenHandSuccessSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '知识库配置已保存。',
          zhHant: '知識庫設定已儲存。',
          en: 'Knowledge Base settings saved.',
          fr: 'Paramètres de la base de connaissances enregistrés.',
          de: 'Wissensdatenbank-Einstellungen gespeichert.',
          ja: 'ナレッジベース設定を保存しました。',
        ),
      );
    } catch (error, stack) {
      var errorMessage = knowledgeBaseFailureMessage(
        error,
        fallback: '保存知识库配置失败，请稍后重试。',
      );
      if (knowledgeSettingsSaved) {
        try {
          await knowledgeController.updateSettings(previousSettings);
        } catch (rollbackError, rollbackStack) {
          errorMessage = '$errorMessage\n知识库配置回滚失败，请重启应用后重试。';
          silentLog(
            'knowledge_base_config_dialog',
            '回滚设置',
            rollbackError,
            rollbackStack,
          );
        }
      }
      silentLog('knowledge_base_config_dialog', '保存设置', error, stack);
      if (mounted) {
        showOpenHandErrorSnack(context, errorMessage);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final knowledgeController = context.watch<KnowledgeBaseController>();
    final pluginController = context.read<PluginServiceController>();
    // 只关心「当前正在检测哪个插件」，不必跟着插件控制器的其余变更重建。
    final checkingPluginId = context.select<PluginServiceController, String?>(
      (controller) => controller.checkingPluginId,
    );
    final settingsController = context.watch<SettingsController>();
    final embeddingModels = _embeddingModels(settingsController.aiModels);
    final rerankModels = _rerankModels(settingsController.aiModels);
    final readerModels = _readerModels(settingsController.aiModels);
    final dependencies = knowledgeController.dependencies(pluginController);
    final dependencyRefreshing =
        _dependencyRefreshFuture != null ||
        _knowledgeDependencyPluginIds.contains(checkingPluginId);
    final t = openHandTextResolver(context);

    final embeddingModelSupportsRerank =
        _selectedEmbeddingProfile(embeddingModels)?.supportsRerank == true;
    final skipModelRerankEffective =
        _settings.rerankMode == KnowledgeRerankMode.model &&
        _settings.skipModelRerankWhenEmbeddingSupportsRerank &&
        embeddingModelSupportsRerank;
    return buildOpenHandAlertDialog(
      title: Text(
        t(
          zh: '知识库配置',
          zhHant: '知識庫設定',
          en: 'Knowledge Base Settings',
          fr: 'Paramètres de la base de connaissances',
          de: 'Wissensdatenbank-Einstellungen',
          ja: 'ナレッジベース設定',
        ),
      ),
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
                title: t(
                  zh: '嵌入模型',
                  zhHant: '嵌入模型',
                  en: 'Embedding Model',
                  fr: 'Modèle d’embedding',
                  de: 'Embedding-Modell',
                  ja: '埋め込みモデル',
                ),
                icon: Icons.hub_outlined,
                subtitle: t(
                  zh: '选择具备嵌入生成能力的模型，并统一调整向量输出、请求韧性与缓存策略。',
                  zhHant: '選擇具備嵌入生成能力的模型，並統一調整向量輸出、請求韌性與快取策略。',
                  en: 'Choose an embedding-capable model and tune vector output, request resilience, and caching together.',
                  fr: 'Choisissez un modèle capable d’embedding et ajustez la sortie vectorielle, la résilience des requêtes et le cache.',
                  de: 'Wählen Sie ein embedding-fähiges Modell und stimmen Sie Vektorausgabe, Anfrage-Resilienz und Cache gemeinsam ab.',
                  ja: '埋め込み生成に対応したモデルを選び、ベクトル出力、リクエスト耐性、キャッシュをまとめて調整します。',
                ),
                children: _embeddingModelSectionChildren(
                  context: context,
                  embeddingModels: embeddingModels,
                  settingsController: settingsController,
                ),
              ),
              _section(
                context,
                title: t(
                  zh: '向量库',
                  zhHant: '向量庫',
                  en: 'Vector Store',
                  fr: 'Stockage vectoriel',
                  de: 'Vektorspeicher',
                  ja: 'ベクトルストア',
                ),
                icon: Icons.storage_outlined,
                children: [
                  _readonly(
                    context,
                    t(
                      zh: '类型',
                      zhHant: '類型',
                      en: 'Type',
                      fr: 'Type',
                      de: 'Typ',
                      ja: '種類',
                    ),
                    'Qdrant',
                  ),
                  _field(
                    _qdrantHost,
                    t(
                      zh: 'Qdrant 主机',
                      zhHant: 'Qdrant 主機',
                      en: 'Qdrant host',
                      fr: 'Hôte Qdrant',
                      de: 'Qdrant-Host',
                      ja: 'Qdrant ホスト',
                    ),
                  ),
                  _field(
                    _qdrantRestPort,
                    t(
                      zh: 'REST 端口',
                      zhHant: 'REST 連接埠',
                      en: 'REST port',
                      fr: 'Port REST',
                      de: 'REST-Port',
                      ja: 'REST ポート',
                    ),
                  ),
                  _field(
                    _qdrantGrpcPort,
                    t(
                      zh: 'gRPC 端口',
                      zhHant: 'gRPC 連接埠',
                      en: 'gRPC port',
                      fr: 'Port gRPC',
                      de: 'gRPC-Port',
                      ja: 'gRPC ポート',
                    ),
                  ),
                  _field(
                    _collectionName,
                    t(
                      zh: 'Collection 名称（留空自动生成）',
                      zhHant: 'Collection 名稱（留空自動產生）',
                      en: 'Collection name (auto when empty)',
                      fr: 'Nom de collection (auto si vide)',
                      de: 'Collection-Name (leer = automatisch)',
                      ja: 'コレクション名（空なら自動）',
                    ),
                  ),
                  _dropdown(
                    label: t(
                      zh: '距离度量',
                      zhHant: '距離度量',
                      en: 'Distance metric',
                      fr: 'Métrique de distance',
                      de: 'Distanzmetrik',
                      ja: '距離メトリック',
                    ),
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
                  _field(_hnswM, 'HNSW M'),
                  _field(_hnswEfConstruct, 'HNSW ef_construct'),
                  _field(
                    _searchEf,
                    t(
                      zh: '搜索 hnsw_ef',
                      zhHant: '搜尋 hnsw_ef',
                      en: 'Search hnsw_ef',
                      fr: 'Recherche hnsw_ef',
                      de: 'Suche hnsw_ef',
                      ja: '検索 hnsw_ef',
                    ),
                  ),
                  _switch(
                    t(
                      zh: '自动启动 sidecar',
                      zhHant: '自動啟動 sidecar',
                      en: 'Auto-start sidecar',
                      fr: 'Démarrer le sidecar automatiquement',
                      de: 'Sidecar automatisch starten',
                      ja: 'sidecar を自動起動',
                    ),
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
                title: t(
                  zh: '文档导入与分块',
                  zhHant: '文件匯入與分塊',
                  en: 'Document Import and Chunking',
                  fr: 'Import et découpage des documents',
                  de: 'Dokumentimport und Chunking',
                  ja: 'ドキュメントのインポートとチャンク化',
                ),
                icon: Icons.segment_outlined,
                subtitle: t(
                  zh: '支持 ${KnowledgeDocumentParserRegistry.supportedFilesLabelZh}',
                  zhHant:
                      '支援 ${KnowledgeDocumentParserRegistry.supportedFilesLabelZh}',
                  en: 'Supports ${KnowledgeDocumentParserRegistry.supportedFilesLabelEn}',
                  fr: 'Prend en charge ${KnowledgeDocumentParserRegistry.supportedFilesLabelEn}',
                  de: 'Unterstützt ${KnowledgeDocumentParserRegistry.supportedFilesLabelEn}',
                  ja: '${KnowledgeDocumentParserRegistry.supportedFilesLabelEn} に対応',
                ),
                children: [
                  _dropdown(
                    label: t(
                      zh: '分块策略',
                      zhHant: '分塊策略',
                      en: 'Chunk strategy',
                      fr: 'Stratégie de découpage',
                      de: 'Chunking-Strategie',
                      ja: 'チャンク戦略',
                    ),
                    value: _settings.chunkStrategy,
                    values: _knowledgeChunkStrategies,
                    itemLabel: (value) => switch (value) {
                      KnowledgeChunkStrategy.markdownHeadingRecursive => t(
                        zh: 'Markdown 标题递归窗口',
                        zhHant: 'Markdown 標題遞迴視窗',
                        en: 'Markdown heading recursive windows',
                        fr: 'Fenêtres récursives par titres Markdown',
                        de: 'Rekursive Markdown-Überschriftenfenster',
                        ja: 'Markdown 見出し再帰ウィンドウ',
                      ),
                      KnowledgeChunkStrategy.paragraphWindow => t(
                        zh: '段落窗口',
                        zhHant: '段落視窗',
                        en: 'Paragraph windows',
                        fr: 'Fenêtres par paragraphes',
                        de: 'Absatzfenster',
                        ja: '段落ウィンドウ',
                      ),
                      KnowledgeChunkStrategy.fixedTokenWindow => t(
                        zh: '固定 token 窗口',
                        zhHant: '固定 token 視窗',
                        en: 'Fixed token windows',
                        fr: 'Fenêtres de tokens fixes',
                        de: 'Feste Token-Fenster',
                        ja: '固定トークンウィンドウ',
                      ),
                      KnowledgeChunkStrategy.semanticLight => t(
                        zh: '轻量语义边界',
                        zhHant: '輕量語意邊界',
                        en: 'Light semantic boundaries',
                        fr: 'Frontières sémantiques légères',
                        de: 'Leichte semantische Grenzen',
                        ja: '軽量セマンティック境界',
                      ),
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
                    label: t(
                      zh: '文档解析引擎',
                      zhHant: '文件解析引擎',
                      en: 'Document parser engine',
                      fr: 'Moteur d’analyse de document',
                      de: 'Dokumentparser',
                      ja: 'ドキュメント解析エンジン',
                    ),
                    value: _settings.documentParsingEngine,
                    values: const ['auto'],
                    itemLabel: (value) => switch (value) {
                      'auto' => t(
                        zh: '自动选择',
                        zhHant: '自動選擇',
                        en: 'Auto registry',
                        fr: 'Registre automatique',
                        de: 'Automatische Registry',
                        ja: '自動レジストリ',
                      ),
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
                    label: t(
                      zh: 'Office 解析引擎',
                      zhHant: 'Office 解析引擎',
                      en: 'Office parser engine',
                      fr: 'Moteur d’analyse Office',
                      de: 'Office-Parser',
                      ja: 'Office 解析エンジン',
                    ),
                    value: _settings.officeParsingEngine,
                    values: const ['open_xml'],
                    itemLabel: (value) => switch (value) {
                      'open_xml' => t(
                        zh: 'Open XML 内置解析',
                        zhHant: 'Open XML 內建解析',
                        en: 'Built-in Open XML',
                        fr: 'Open XML intégré',
                        de: 'Integriertes Open XML',
                        ja: '内蔵 Open XML',
                      ),
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
                    label: t(
                      zh: 'PDF 解析引擎',
                      zhHant: 'PDF 解析引擎',
                      en: 'PDF parser engine',
                      fr: 'Moteur d’analyse PDF',
                      de: 'PDF-Parser',
                      ja: 'PDF 解析エンジン',
                    ),
                    value: _settings.pdfParsingEngine,
                    values: const ['basic_text_stream'],
                    itemLabel: (value) => switch (value) {
                      'basic_text_stream' => t(
                        zh: '基础文本流解析',
                        zhHant: '基礎文字流解析',
                        en: 'Basic text-stream extraction',
                        fr: 'Extraction basique du flux texte',
                        de: 'Einfache Textstrom-Extraktion',
                        ja: '基本テキストストリーム抽出',
                      ),
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
                    label: t(
                      zh: 'HTML 解析策略',
                      zhHant: 'HTML 解析策略',
                      en: 'HTML parsing strategy',
                      fr: 'Stratégie d’analyse HTML',
                      de: 'HTML-Parsing-Strategie',
                      ja: 'HTML 解析戦略',
                    ),
                    value: _settings.htmlParsingMode,
                    values: const ['readable_text', 'plain_text'],
                    itemLabel: (value) => switch (value) {
                      'readable_text' => t(
                        zh: '结构化可读文本',
                        zhHant: '結構化可讀文字',
                        en: 'Readable structure',
                        fr: 'Structure lisible',
                        de: 'Lesbare Struktur',
                        ja: '読みやすい構造',
                      ),
                      'plain_text' => t(
                        zh: '纯文本提取',
                        zhHant: '純文字擷取',
                        en: 'Plain text',
                        fr: 'Texte brut',
                        de: 'Nur Text',
                        ja: 'プレーンテキスト',
                      ),
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
                    label: t(
                      zh: '结构化数据策略',
                      zhHant: '結構化資料策略',
                      en: 'Structured data strategy',
                      fr: 'Stratégie des données structurées',
                      de: 'Strategie für strukturierte Daten',
                      ja: '構造化データ戦略',
                    ),
                    value: _settings.structuredDataParsingMode,
                    values: const ['readable_markdown', 'raw_fenced'],
                    itemLabel: (value) => switch (value) {
                      'readable_markdown' => t(
                        zh: '可读 Markdown',
                        zhHant: '可讀 Markdown',
                        en: 'Readable Markdown',
                        fr: 'Markdown lisible',
                        de: 'Lesbares Markdown',
                        ja: '読みやすい Markdown',
                      ),
                      'raw_fenced' => t(
                        zh: '原文代码块',
                        zhHant: '原文程式碼區塊',
                        en: 'Raw fenced block',
                        fr: 'Bloc brut clôturé',
                        de: 'Roher Codeblock',
                        ja: '生の fenced ブロック',
                      ),
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
                    label: t(
                      zh: '表格解析策略',
                      zhHant: '表格解析策略',
                      en: 'Table parsing strategy',
                      fr: 'Stratégie d’analyse des tableaux',
                      de: 'Tabellen-Parsing-Strategie',
                      ja: '表解析戦略',
                    ),
                    value: _settings.spreadsheetParsingMode,
                    values: const ['markdown_table', 'row_blocks'],
                    itemLabel: (value) => switch (value) {
                      'markdown_table' => t(
                        zh: 'Markdown 表格',
                        zhHant: 'Markdown 表格',
                        en: 'Markdown table',
                        fr: 'Tableau Markdown',
                        de: 'Markdown-Tabelle',
                        ja: 'Markdown 表',
                      ),
                      'row_blocks' => t(
                        zh: '行块文本',
                        zhHant: '列區塊文字',
                        en: 'Row blocks',
                        fr: 'Blocs de lignes',
                        de: 'Zeilenblöcke',
                        ja: '行ブロック',
                      ),
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
                    label: t(
                      zh: '演示文稿策略',
                      zhHant: '簡報策略',
                      en: 'Presentation strategy',
                      fr: 'Stratégie de présentation',
                      de: 'Präsentationsstrategie',
                      ja: 'プレゼンテーション戦略',
                    ),
                    value: _settings.presentationParsingMode,
                    values: const ['slide_text', 'outline'],
                    itemLabel: (value) => switch (value) {
                      'slide_text' => t(
                        zh: '按幻灯片文本',
                        zhHant: '按投影片文字',
                        en: 'Slide text',
                        fr: 'Texte des diapositives',
                        de: 'Folientext',
                        ja: 'スライドテキスト',
                      ),
                      'outline' => t(
                        zh: '大纲文本',
                        zhHant: '大綱文字',
                        en: 'Outline',
                        fr: 'Plan',
                        de: 'Gliederung',
                        ja: 'アウトライン',
                      ),
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
                    t(
                      zh: '子分块目标 token',
                      zhHant: '子分塊目標 token',
                      en: 'Child target tokens',
                      fr: 'Tokens cible enfant',
                      de: 'Ziel-Tokens je Kindabschnitt',
                      ja: '子チャンク目標トークン',
                    ),
                  ),
                  _field(
                    _hardMaxTokens,
                    t(
                      zh: '子分块硬上限 token',
                      zhHant: '子分塊硬上限 token',
                      en: 'Child hard max tokens',
                      fr: 'Limite dure de tokens enfant',
                      de: 'Harte Token-Obergrenze je Kindabschnitt',
                      ja: '子チャンク最大トークン',
                    ),
                  ),
                  _field(
                    _overlapTokens,
                    t(
                      zh: '重叠 token',
                      zhHant: '重疊 token',
                      en: 'Overlap tokens',
                      fr: 'Tokens de chevauchement',
                      de: 'Überlappungs-Tokens',
                      ja: '重複トークン',
                    ),
                  ),
                  _field(
                    _maxFileSizeMb,
                    t(
                      zh: '单文件 MB 上限',
                      zhHant: '單檔 MB 上限',
                      en: 'Max file MB',
                      fr: 'Taille max fichier (Mo)',
                      de: 'Max. Dateigröße (MB)',
                      ja: 'ファイル上限 MB',
                    ),
                  ),
                  _switch(
                    t(
                      zh: '复制导入文件',
                      zhHant: '複製匯入檔案',
                      en: 'Copy imported files',
                      fr: 'Copier les fichiers importés',
                      de: 'Importierte Dateien kopieren',
                      ja: 'インポートファイルをコピー',
                    ),
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
                    t(
                      zh: '监听原始文件',
                      zhHant: '監聽原始檔案',
                      en: 'Watch original files',
                      fr: 'Surveiller les fichiers source',
                      de: 'Originaldateien überwachen',
                      ja: '元ファイルを監視',
                    ),
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
                    t(
                      zh: 'parent-child 检索',
                      zhHant: 'parent-child 檢索',
                      en: 'Parent-child retrieval',
                      fr: 'Recherche parent-enfant',
                      de: 'Parent-Child-Abruf',
                      ja: '親子検索',
                    ),
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
                title: t(
                  zh: '标签与时间',
                  zhHant: '標籤與時間',
                  en: 'Tags and Time',
                  fr: 'Étiquettes et temps',
                  de: 'Tags und Zeit',
                  ja: 'タグと時間',
                ),
                icon: Icons.sell_outlined,
                children: [
                  _switch(
                    t(
                      zh: '从路径生成标签',
                      zhHant: '從路徑產生標籤',
                      en: 'Path-derived tags',
                      fr: 'Étiquettes depuis le chemin',
                      de: 'Tags aus Pfaden ableiten',
                      ja: 'パスからタグを生成',
                    ),
                    _settings.autoPathTags,
                    (value) {
                      setState(
                        () =>
                            _settings = _settings.copyWith(autoPathTags: value),
                      );
                    },
                  ),
                  _switch(
                    t(
                      zh: '读取 front matter 标签',
                      zhHant: '讀取 front matter 標籤',
                      en: 'Front matter tags',
                      fr: 'Étiquettes front matter',
                      de: 'Front-Matter-Tags',
                      ja: 'front matter タグを読む',
                    ),
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
                    t(
                      zh: '自动标签建议',
                      zhHant: '自動標籤建議',
                      en: 'Auto tag suggestions',
                      fr: 'Suggestions automatiques d’étiquettes',
                      de: 'Automatische Tag-Vorschläge',
                      ja: 'タグを自動提案',
                    ),
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
                    label: t(
                      zh: '文档时间来源',
                      zhHant: '文件時間來源',
                      en: 'Document time source',
                      fr: 'Source de date du document',
                      de: 'Quelle der Dokumentzeit',
                      ja: 'ドキュメント日時の取得元',
                    ),
                    value: _settings.defaultDocumentTimeSource,
                    values: _knowledgeDocumentTimeSources,
                    itemLabel: (value) => switch (value) {
                      'front_matter' => 'Front matter',
                      'file_modified_at' => t(
                        zh: '文件修改时间',
                        zhHant: '檔案修改時間',
                        en: 'File modified time',
                        fr: 'Date de modification du fichier',
                        de: 'Dateiänderungszeit',
                        ja: 'ファイル更新日時',
                      ),
                      'imported_at' => t(
                        zh: '导入时间',
                        zhHant: '匯入時間',
                        en: 'Imported time',
                        fr: 'Date d’import',
                        de: 'Importzeit',
                        ja: 'インポート日時',
                      ),
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
                    t(
                      zh: '解析自然语言时间',
                      zhHant: '解析自然語言時間',
                      en: 'Parse natural language time',
                      fr: 'Analyser les dates en langage naturel',
                      de: 'Natürliche Zeitangaben parsen',
                      ja: '自然言語の日時を解析',
                    ),
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
                    t(
                      zh: '最新/最近 boost',
                      zhHant: '最新/最近 boost',
                      en: 'Recency boost',
                      fr: 'Boost de récence',
                      de: 'Aktualitäts-Boost',
                      ja: '新しさブースト',
                    ),
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
                title: t(
                  zh: '检索召回',
                  zhHant: '檢索召回',
                  en: 'Retrieval Recall',
                  fr: 'Rappel de recherche',
                  de: 'Abruf',
                  ja: '検索リコール',
                ),
                icon: Icons.travel_explore_rounded,
                children: [
                  _field(
                    _topN,
                    t(
                      zh: '召回 topN',
                      zhHant: '召回 topN',
                      en: 'topN recall',
                      fr: 'Rappel topN',
                      de: 'Abruf topN',
                      ja: '取得 topN',
                    ),
                  ),
                  _field(
                    _topK,
                    t(
                      zh: '最终 topK',
                      zhHant: '最終 topK',
                      en: 'topK final',
                      fr: 'TopK final',
                      de: 'Finales topK',
                      ja: '最終 topK',
                    ),
                  ),
                  _field(
                    _minSimilarity,
                    t(
                      zh: '最低相似度',
                      zhHant: '最低相似度',
                      en: 'Min similarity',
                      fr: 'Similarité min.',
                      de: 'Min. Ähnlichkeit',
                      ja: '最小類似度',
                    ),
                  ),
                  _field(
                    _sourceCap,
                    t(
                      zh: '单来源上限',
                      zhHant: '單來源上限',
                      en: 'Source cap',
                      fr: 'Limite par source',
                      de: 'Limit je Quelle',
                      ja: 'ソース上限',
                    ),
                  ),
                  _dropdown(
                    label: t(
                      zh: '标签过滤模式',
                      zhHant: '標籤篩選模式',
                      en: 'Tag filter mode',
                      fr: 'Mode de filtre des étiquettes',
                      de: 'Tag-Filtermodus',
                      ja: 'タグフィルターモード',
                    ),
                    value: _settings.tagFilterMode,
                    values: KnowledgeTagFilterMode.values,
                    itemLabel: (value) => switch (value) {
                      KnowledgeTagFilterMode.any => t(
                        zh: '任一标签命中',
                        zhHant: '任一標籤命中',
                        en: 'Any tag',
                        fr: 'N’importe quelle étiquette',
                        de: 'Beliebiger Tag',
                        ja: '任意のタグ',
                      ),
                      KnowledgeTagFilterMode.all => t(
                        zh: '全部标签命中',
                        zhHant: '全部標籤命中',
                        en: 'All tags',
                        fr: 'Toutes les étiquettes',
                        de: 'Alle Tags',
                        ja: 'すべてのタグ',
                      ),
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
                    label: t(
                      zh: '日期过滤模式',
                      zhHant: '日期篩選模式',
                      en: 'Date filter mode',
                      fr: 'Mode de filtre de date',
                      de: 'Datumsfiltermodus',
                      ja: '日付フィルターモード',
                    ),
                    value: _settings.dateFilterMode,
                    values: KnowledgeDateFilterMode.values,
                    itemLabel: (value) => switch (value) {
                      KnowledgeDateFilterMode.hardWhenExplicit => t(
                        zh: '显式时间硬过滤',
                        zhHant: '顯式時間硬篩選',
                        en: 'Hard when explicit',
                        fr: 'Strict si explicite',
                        de: 'Hart bei expliziter Zeit',
                        ja: '明示時は厳密',
                      ),
                      KnowledgeDateFilterMode.softBoost => t(
                        zh: '软加权',
                        zhHant: '軟加權',
                        en: 'Soft boost',
                        fr: 'Boost souple',
                        de: 'Weicher Boost',
                        ja: 'ソフトブースト',
                      ),
                      KnowledgeDateFilterMode.off => t(
                        zh: '关闭',
                        zhHant: '關閉',
                        en: 'Off',
                        fr: 'Désactivé',
                        de: 'Aus',
                        ja: 'オフ',
                      ),
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
                  _field(
                    _vectorWeight,
                    t(
                      zh: '向量权重',
                      zhHant: '向量權重',
                      en: 'Vector weight',
                      fr: 'Poids vectoriel',
                      de: 'Vektorgewicht',
                      ja: 'ベクトル重み',
                    ),
                  ),
                  _field(
                    _titleWeight,
                    t(
                      zh: '标题权重',
                      zhHant: '標題權重',
                      en: 'Title weight',
                      fr: 'Poids du titre',
                      de: 'Titelgewicht',
                      ja: 'タイトル重み',
                    ),
                  ),
                  _field(
                    _tagWeight,
                    t(
                      zh: '标签权重',
                      zhHant: '標籤權重',
                      en: 'Tag weight',
                      fr: 'Poids des étiquettes',
                      de: 'Tag-Gewicht',
                      ja: 'タグ重み',
                    ),
                  ),
                  _field(
                    _timeWeight,
                    t(
                      zh: '时间权重',
                      zhHant: '時間權重',
                      en: 'Time weight',
                      fr: 'Poids temporel',
                      de: 'Zeitgewicht',
                      ja: '時間重み',
                    ),
                  ),
                  _field(
                    _exactPhraseWeight,
                    t(
                      zh: '精确短语权重',
                      zhHant: '精確片語權重',
                      en: 'Exact phrase weight',
                      fr: 'Poids des phrases exactes',
                      de: 'Gewicht exakter Phrasen',
                      ja: '完全一致フレーズ重み',
                    ),
                  ),
                  _field(
                    _sourceQualityWeight,
                    t(
                      zh: '来源质量权重',
                      zhHant: '來源品質權重',
                      en: 'Source quality weight',
                      fr: 'Poids de qualité de source',
                      de: 'Quellenqualitätsgewicht',
                      ja: 'ソース品質重み',
                    ),
                  ),
                ],
              ),
              _section(
                context,
                title: t(
                  zh: '重排与去重',
                  zhHant: '重排與去重',
                  en: 'Rerank and Deduplication',
                  fr: 'Reclassement et déduplication',
                  de: 'Reranking und Deduplizierung',
                  ja: '再ランクと重複排除',
                ),
                icon: Icons.filter_alt_outlined,
                children: [
                  _dropdown(
                    label: t(
                      zh: '重排序方式',
                      zhHant: '重排序方式',
                      en: 'Rerank mode',
                      fr: 'Mode de reclassement',
                      de: 'Reranking-Modus',
                      ja: '再ランク方式',
                    ),
                    value: _settings.rerankMode,
                    values: KnowledgeRerankMode.values,
                    itemLabel: (value) => switch (value) {
                      KnowledgeRerankMode.off => t(
                        zh: '关闭',
                        zhHant: '關閉',
                        en: 'Off',
                        fr: 'Désactivé',
                        de: 'Aus',
                        ja: 'オフ',
                      ),
                      KnowledgeRerankMode.localHybrid => t(
                        zh: '本地混合评分',
                        zhHant: '本地混合評分',
                        en: 'Local hybrid scoring',
                        fr: 'Score hybride local',
                        de: 'Lokale Hybridbewertung',
                        ja: 'ローカル混合スコア',
                      ),
                      KnowledgeRerankMode.mmr => t(
                        zh: 'MMR 多样性重排',
                        zhHant: 'MMR 多樣性重排',
                        en: 'MMR diversity',
                        fr: 'Diversité MMR',
                        de: 'MMR-Diversität',
                        ja: 'MMR 多様性',
                      ),
                      KnowledgeRerankMode.model => t(
                        zh: '模型重排序',
                        zhHant: '模型重排序',
                        en: 'Model rerank',
                        fr: 'Reclassement par modèle',
                        de: 'Modell-Reranking',
                        ja: 'モデル再ランク',
                      ),
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
                                t(
                                  zh: '双能力嵌入模型跳过额外重排',
                                  zhHant: '雙能力嵌入模型跳過額外重排',
                                  en: 'Skip extra rerank for dual-capability embeddings',
                                  fr: 'Ignorer le reclassement supplémentaire pour les embeddings à double capacité',
                                  de: 'Zusätzliches Reranking bei Dual-Capability-Embeddings überspringen',
                                  ja: '両対応の埋め込みモデルでは追加再ランクを省略',
                                ),
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
                              kOpenHandGap12,
                              if (skipModelRerankEffective)
                                KnowledgeDialogNotice(
                                  icon: Icons.check_circle_outline_rounded,
                                  message: t(
                                    zh: '当前嵌入模型同时具备“嵌入生成”和“重排序”能力，检索时会直接采用向量召回顺序，不再额外请求重排序模型。',
                                    zhHant:
                                        '目前嵌入模型同時具備「嵌入生成」與「重排序」能力，檢索時會直接採用向量召回順序，不再額外請求重排序模型。',
                                    en: 'The current embedding model also supports rerank. Retrieval will use vector recall order without an extra rerank request.',
                                    fr: 'Le modèle d’embedding actuel prend aussi en charge le reclassement. La recherche utilisera l’ordre de rappel vectoriel sans requête supplémentaire.',
                                    de: 'Das aktuelle Embedding-Modell unterstützt auch Reranking. Der Abruf nutzt die Vektor-Reihenfolge ohne zusätzliche Reranking-Anfrage.',
                                    ja: '現在の埋め込みモデルは再ランクにも対応しています。検索では追加リクエストなしでベクトル取得順を使います。',
                                  ),
                                )
                              else if (rerankModels.isEmpty)
                                KnowledgeDialogNotice(
                                  icon: Icons.filter_alt_outlined,
                                  message: t(
                                    zh: '没有已开启“重排序”的模型。请先在设置的模型配置中启用该能力。',
                                    zhHant: '沒有已啟用「重排序」的模型。請先在設定的模型配置中啟用該能力。',
                                    en: 'No model profile has Rerank enabled. Enable it in model settings first.',
                                    fr: 'Aucun profil de modèle n’a le reclassement activé. Activez-le d’abord dans les paramètres du modèle.',
                                    de: 'Kein Modellprofil hat Rerank aktiviert. Aktivieren Sie es zuerst in den Modelleinstellungen.',
                                    ja: '再ランクが有効なモデルプロファイルがありません。先にモデル設定で有効にしてください。',
                                  ),
                                )
                              else ...[
                                if (_settings
                                        .skipModelRerankWhenEmbeddingSupportsRerank &&
                                    !embeddingModelSupportsRerank) ...[
                                  KnowledgeDialogNotice(
                                    icon: Icons.info_outline_rounded,
                                    message: t(
                                      zh: '当前嵌入模型未标记“重排序”能力，仍会请求下方选择的重排序模型。',
                                      zhHant:
                                          '目前嵌入模型未標記「重排序」能力，仍會請求下方選擇的重排序模型。',
                                      en: 'The current embedding model is not marked rerank-capable, so the selected rerank model will still be requested.',
                                      fr: 'Le modèle d’embedding actuel n’est pas marqué compatible reclassement ; le modèle choisi ci-dessous sera donc utilisé.',
                                      de: 'Das aktuelle Embedding-Modell ist nicht als Rerank-fähig markiert, daher wird das unten gewählte Rerank-Modell genutzt.',
                                      ja: '現在の埋め込みモデルは再ランク対応としてマークされていないため、下で選択した再ランクモデルをリクエストします。',
                                    ),
                                  ),
                                  kOpenHandGap12,
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
                                  labelZhHant: '重排序模型',
                                  labelFr: 'Modèle de reclassement',
                                  labelDe: 'Rerank-Modell',
                                  labelJa: '再ランクモデル',
                                  helperZh: '仅显示已开启“重排序”的模型配置。',
                                  helperEn:
                                      'Only rerank-capable model profiles are shown.',
                                  helperZhHant: '僅顯示已啟用「重排序」的模型配置。',
                                  helperFr:
                                      'Seuls les profils compatibles reclassement sont affichés.',
                                  helperDe:
                                      'Es werden nur Rerank-fähige Modellprofile angezeigt.',
                                  helperJa: '再ランク対応のモデルプロファイルのみ表示します。',
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
                    _field(_mmrLambda, 'MMR lambda'),
                  _switch(
                    t(
                      zh: '邻居扩展',
                      zhHant: '鄰近擴展',
                      en: 'Neighbor expansion',
                      fr: 'Expansion voisine',
                      de: 'Nachbarerweiterung',
                      ja: '近傍拡張',
                    ),
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
                    t(
                      zh: '父级扩展',
                      zhHant: '父級擴展',
                      en: 'Parent expansion',
                      fr: 'Expansion parent',
                      de: 'Parent-Erweiterung',
                      ja: '親拡張',
                    ),
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
                    t(
                      zh: '单来源最终 chunk 上限',
                      zhHant: '單來源最終 chunk 上限',
                      en: 'Max chunks per source',
                      fr: 'Chunks max par source',
                      de: 'Max. Chunks je Quelle',
                      ja: 'ソースごとの最大チャンク数',
                    ),
                  ),
                  if (_settings.rerankMode == KnowledgeRerankMode.model &&
                      !skipModelRerankEffective) ...[
                    _field(_rerankTopN, 'Rerank topN'),
                    _field(
                      _rerankTimeout,
                      t(
                        zh: 'Rerank 超时秒数',
                        zhHant: 'Rerank 逾時秒數',
                        en: 'Rerank timeout seconds',
                        fr: 'Délai de reclassement (s)',
                        de: 'Rerank-Timeout in Sekunden',
                        ja: '再ランクタイムアウト秒数',
                      ),
                    ),
                  ],
                ],
              ),
              _section(
                context,
                title: t(
                  zh: 'Prompt 追加',
                  zhHant: 'Prompt 追加',
                  en: 'Prompt Append',
                  fr: 'Ajout au prompt',
                  de: 'Prompt-Anhang',
                  ja: 'Prompt 追加',
                ),
                icon: Icons.post_add_outlined,
                children: [
                  _field(
                    _maxPromptChunks,
                    t(
                      zh: '最多追加 chunk',
                      zhHant: '最多追加 chunk',
                      en: 'Max prompt chunks',
                      fr: 'Chunks max ajoutés',
                      de: 'Max. Prompt-Chunks',
                      ja: '最大追加チャンク数',
                    ),
                  ),
                  _field(
                    _maxPromptTokens,
                    t(
                      zh: '最大追加 token',
                      zhHant: '最大追加 token',
                      en: 'Max prompt tokens',
                      fr: 'Tokens max ajoutés',
                      de: 'Max. Prompt-Tokens',
                      ja: '最大追加トークン',
                    ),
                  ),
                  _switch(
                    t(
                      zh: '包含 score',
                      zhHant: '包含 score',
                      en: 'Include score',
                      fr: 'Inclure le score',
                      de: 'Score einschließen',
                      ja: 'スコアを含める',
                    ),
                    _settings.includeScore,
                    (value) {
                      setState(
                        () =>
                            _settings = _settings.copyWith(includeScore: value),
                      );
                    },
                  ),
                  _switch(
                    t(
                      zh: '包含标签',
                      zhHant: '包含標籤',
                      en: 'Include tags',
                      fr: 'Inclure les étiquettes',
                      de: 'Tags einschließen',
                      ja: 'タグを含める',
                    ),
                    _settings.includeTags,
                    (value) {
                      setState(
                        () =>
                            _settings = _settings.copyWith(includeTags: value),
                      );
                    },
                  ),
                  _switch(
                    t(
                      zh: '包含日期',
                      zhHant: '包含日期',
                      en: 'Include date',
                      fr: 'Inclure la date',
                      de: 'Datum einschließen',
                      ja: '日付を含める',
                    ),
                    _settings.includeDate,
                    (value) {
                      setState(
                        () =>
                            _settings = _settings.copyWith(includeDate: value),
                      );
                    },
                  ),
                  _switch(
                    t(
                      zh: '包含来源路径',
                      zhHant: '包含來源路徑',
                      en: 'Include source path',
                      fr: 'Inclure le chemin source',
                      de: 'Quellpfad einschließen',
                      ja: 'ソースパスを含める',
                    ),
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
                    t(
                      zh: '包含 chunk ID',
                      zhHant: '包含 chunk ID',
                      en: 'Include chunk ID',
                      fr: 'Inclure l’ID du chunk',
                      de: 'Chunk-ID einschließen',
                      ja: 'チャンク ID を含める',
                    ),
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
                title: t(
                  zh: '发送时行为',
                  zhHant: '傳送時行為',
                  en: 'Send-time Behavior',
                  fr: 'Comportement à l’envoi',
                  de: 'Verhalten beim Senden',
                  ja: '送信時の動作',
                ),
                icon: Icons.send_time_extension_outlined,
                children: [
                  _dropdown(
                    label: t(
                      zh: '检索失败策略',
                      zhHant: '檢索失敗策略',
                      en: 'Retrieval failure strategy',
                      fr: 'Stratégie en cas d’échec de recherche',
                      de: 'Strategie bei Abruffehlern',
                      ja: '検索失敗時の戦略',
                    ),
                    value: _settings.failureStrategy,
                    values: KnowledgeFailureStrategy.values,
                    itemLabel: (value) => switch (value) {
                      KnowledgeFailureStrategy.failOpen => t(
                        zh: '失败后继续发送',
                        zhHant: '失敗後繼續傳送',
                        en: 'Fail open',
                        fr: 'Continuer après échec',
                        de: 'Bei Fehler fortfahren',
                        ja: '失敗しても送信',
                      ),
                      KnowledgeFailureStrategy.failClosed => t(
                        zh: '失败后阻止发送',
                        zhHant: '失敗後阻止傳送',
                        en: 'Fail closed',
                        fr: 'Bloquer après échec',
                        de: 'Bei Fehler blockieren',
                        ja: '失敗時は送信を止める',
                      ),
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
                    t(
                      zh: 'Embedding 失败继续发送',
                      zhHant: 'Embedding 失敗繼續傳送',
                      en: 'Fail open on embedding error',
                      fr: 'Continuer si l’embedding échoue',
                      de: 'Bei Embedding-Fehler fortfahren',
                      ja: '埋め込み失敗時も送信',
                    ),
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
                    t(
                      zh: '无命中继续发送',
                      zhHant: '無命中繼續傳送',
                      en: 'Continue when no hits',
                      fr: 'Continuer sans résultat',
                      de: 'Ohne Treffer fortfahren',
                      ja: 'ヒットなしでも送信',
                    ),
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
                    t(
                      zh: '发送前预览',
                      zhHant: '傳送前預覽',
                      en: 'Preview before send',
                      fr: 'Aperçu avant envoi',
                      de: 'Vor dem Senden anzeigen',
                      ja: '送信前プレビュー',
                    ),
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
                title: t(
                  zh: '工具权限',
                  zhHant: '工具權限',
                  en: 'Tool Access',
                  fr: 'Accès aux outils',
                  de: 'Tool-Zugriff',
                  ja: 'ツールアクセス',
                ),
                icon: Icons.admin_panel_settings_outlined,
                children: [
                  _switch(
                    t(
                      zh: '暴露知识库内建工具',
                      zhHant: '暴露知識庫內建工具',
                      en: 'Expose Knowledge Base built-in tools',
                      fr: 'Exposer les outils intégrés de la base de connaissances',
                      de: 'Integrierte Wissensdatenbank-Tools verfügbar machen',
                      ja: 'ナレッジベース内蔵ツールを公開',
                    ),
                    _knowledgeBuiltinToolsEnabled,
                    (value) {
                      setState(() => _knowledgeBuiltinToolsEnabled = value);
                    },
                    subtitle: t(
                      zh: '开启后 KnowledgeSearch / KnowledgeRead 会直接出现在工具目录，由 AI 自主检索和读取；关闭后两个工具同时禁用。',
                      zhHant:
                          '開啟後 KnowledgeSearch / KnowledgeRead 會直接出現在工具目錄，由 AI 自主檢索和讀取；關閉後兩個工具同時停用。',
                      en: 'When enabled, KnowledgeSearch / KnowledgeRead are exposed directly and the AI can decide when to search or read. Disabling turns both tools off.',
                      fr: 'Si activés, KnowledgeSearch / KnowledgeRead apparaissent directement et l’IA choisit quand rechercher ou lire. Les désactiver coupe les deux outils.',
                      de: 'Wenn aktiviert, werden KnowledgeSearch / KnowledgeRead direkt angeboten und die KI entscheidet über Suche oder Lesen. Deaktivieren schaltet beide Tools aus.',
                      ja: '有効にすると KnowledgeSearch / KnowledgeRead が直接ツール一覧に出て、AI が検索や読み取りを判断します。無効にすると両方のツールが停止します。',
                    ),
                  ),
                ],
              ),
              _section(
                context,
                title: t(
                  zh: '维护与诊断',
                  zhHant: '維護與診斷',
                  en: 'Maintenance and Diagnostics',
                  fr: 'Maintenance et diagnostics',
                  de: 'Wartung und Diagnose',
                  ja: 'メンテナンスと診断',
                ),
                icon: Icons.build_circle_outlined,
                children: [
                  _readonly(
                    context,
                    'Collection',
                    _settings.effectiveCollectionName,
                  ),
                  _field(
                    _qdrantMetricsRefreshSeconds,
                    t(
                      zh: 'Qdrant 指标刷新秒数',
                      zhHant: 'Qdrant 指標重新整理秒數',
                      en: 'Qdrant metrics refresh seconds',
                      fr: 'Intervalle métriques Qdrant (s)',
                      de: 'Qdrant-Metrikintervall (s)',
                      ja: 'Qdrant メトリクス更新秒数',
                    ),
                  ),
                  _field(
                    _qdrantLogRetainLines,
                    t(
                      zh: 'Qdrant 日志保留行数',
                      zhHant: 'Qdrant 日誌保留行數',
                      en: 'Qdrant log retained lines',
                      fr: 'Lignes de journal Qdrant conservées',
                      de: 'Behaltene Qdrant-Logzeilen',
                      ja: 'Qdrant ログ保持行数',
                    ),
                  ),
                  _switch(
                    t(
                      zh: '启用危险管理操作',
                      zhHant: '啟用危險管理操作',
                      en: 'Enable dangerous admin operations',
                      fr: 'Activer les opérations admin dangereuses',
                      de: 'Gefährliche Admin-Aktionen aktivieren',
                      ja: '危険な管理操作を有効化',
                    ),
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
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          label: openHandCancelLabel(context),
        ),
        OpenHandDialogActionButton.primary(
          onPressed: _saving ? null : _save,
          icon: Icons.save_rounded,
          busy: _saving,
          label: t(
            zh: '保存',
            zhHant: '儲存',
            en: 'Save',
            fr: 'Enregistrer',
            de: 'Speichern',
            ja: '保存',
          ),
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
    final dependencyMessage = dependencies.localizedMessage(
      Localizations.localeOf(context),
    );
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
                ? openHandLocalizedText(
                    context,
                    zh: '正在重新检测 Docker/Qdrant 状态；当前缓存：$dependencyMessage',
                    zhHant: '正在重新檢測 Docker/Qdrant 狀態；目前快取：$dependencyMessage',
                    en: 'Refreshing Docker/Qdrant status; cached state: $dependencyMessage',
                    fr: 'Actualisation de l’état Docker/Qdrant ; état en cache : $dependencyMessage',
                    de: 'Docker/Qdrant-Status wird aktualisiert; zwischengespeicherter Status: $dependencyMessage',
                    ja: 'Docker/Qdrant の状態を再確認しています。キャッシュ状態: $dependencyMessage',
                  )
                : openHandLocalizedText(
                    context,
                    zh: '知识库依赖未就绪：$dependencyMessage',
                    zhHant: '知識庫依賴尚未就緒：$dependencyMessage',
                    en: 'Knowledge dependencies are unavailable: $dependencyMessage',
                    fr: 'Les dépendances de la base de connaissances sont indisponibles : $dependencyMessage',
                    de: 'Wissensdatenbank-Abhängigkeiten sind nicht verfügbar: $dependencyMessage',
                    ja: 'ナレッジベースの依存関係が利用できません: $dependencyMessage',
                  ),
            trailing: widget.onOpenPlugins == null
                ? null
                : KnowledgeDialogNoticeAction(
                    tone: KnowledgeDialogNoticeTone.warning,
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onOpenPlugins?.call();
                    },
                    icon: Icons.power_rounded,
                    label: openHandLocalizedText(
                      context,
                      zh: '前往插件',
                      zhHant: '前往外掛',
                      en: 'Open Plugins',
                      fr: 'Ouvrir les plugins',
                      de: 'Plugins öffnen',
                      ja: 'プラグインを開く',
                    ),
                  ),
          ),
        ),
      if (!embeddingModelAvailable)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: KnowledgeDialogNotice(
            icon: Icons.hub_outlined,
            message: openHandLocalizedText(
              context,
              zh: '未配置可用的嵌入模型。请选择已开启“嵌入生成”的模型，并确认隐私开关。',
              zhHant: '未設定可用的嵌入模型。請選擇已啟用「嵌入生成」的模型，並確認隱私開關。',
              en: 'No usable embedding model is configured. Choose an embedding-capable model and confirm privacy options.',
              fr: 'Aucun modèle d’embedding utilisable n’est configuré. Choisissez un modèle compatible et vérifiez les options de confidentialité.',
              de: 'Es ist kein nutzbares Embedding-Modell konfiguriert. Wählen Sie ein embedding-fähiges Modell und prüfen Sie die Datenschutzeinstellungen.',
              ja: '利用可能な埋め込みモデルが設定されていません。埋め込み対応モデルを選び、プライバシー設定を確認してください。',
            ),
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
    return switch (value) {
      true => openHandYesLabel(context),
      false => openHandNoLabel(context),
      null => openHandUnknownLabel(context),
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
            curve: kOpenHandSwitchInCurve,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                colorScheme.primary.withValues(alpha: 0.045),
                colorScheme.surfaceContainerHighest.withValues(alpha: 0.68),
              ),
              borderRadius: kOpenHandBorderRadius16,
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
                  labelZhHant: '嵌入模型',
                  labelFr: 'Modèle d’embedding',
                  labelDe: 'Embedding-Modell',
                  labelJa: '埋め込みモデル',
                  helperZh: '只列出具备嵌入生成能力的模型。切换后会同步模型建议参数。',
                  helperEn:
                      'Only embedding-capable models are shown. Changing model syncs recommended parameters.',
                  helperZhHant: '只列出具備嵌入生成能力的模型。切換後會同步模型建議參數。',
                  helperFr:
                      'Seuls les modèles compatibles embedding sont affichés. Le changement synchronise les paramètres recommandés.',
                  helperDe:
                      'Es werden nur embedding-fähige Modelle angezeigt. Beim Wechsel werden empfohlene Parameter synchronisiert.',
                  helperJa: '埋め込み対応モデルのみ表示します。切り替えると推奨パラメータを同期します。',
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
    final ready = profile != null;
    final foreground = ready
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;
    return AnimatedContainer(
      duration: openHandMotionDurationMs(context, 180),
      curve: kOpenHandSwitchInCurve,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:
            (ready
                    ? colorScheme.primaryContainer
                    : colorScheme.surfaceContainerHigh)
                .withValues(alpha: ready ? 0.26 : 0.62),
        borderRadius: kOpenHandBorderRadius14,
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
              kOpenHandHGap7,
              Expanded(
                child: Text(
                  ready
                      ? openHandLocalizedText(
                          context,
                          zh: '模型可用',
                          zhHant: '模型可用',
                          en: 'Model ready',
                          fr: 'Modèle prêt',
                          de: 'Modell bereit',
                          ja: 'モデル利用可能',
                        )
                      : openHandLocalizedText(
                          context,
                          zh: '等待选择',
                          zhHant: '等待選擇',
                          en: 'Pick a model',
                          fr: 'Choisir un modèle',
                          de: 'Modell auswählen',
                          ja: 'モデルを選択',
                        ),
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
          kOpenHandGap7,
          Text(
            ready
                ? trimmedNonEmptyStrings(<Object?>[
                    selectedConfig?.providerLabel,
                    profile.displayName ?? _settings.modelId,
                  ]).join(' / ')
                : openHandLocalizedText(
                    context,
                    zh: '请选择已启用嵌入生成的模型配置。',
                    zhHant: '請選擇已啟用嵌入生成的模型配置。',
                    en: 'Choose an embedding-enabled profile.',
                    fr: 'Choisissez un profil compatible embedding.',
                    de: 'Wählen Sie ein embedding-fähiges Profil.',
                    ja: '埋め込み対応のプロファイルを選択してください。',
                  ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: 1.28,
            ),
          ),
          if (ready) ...[
            kOpenHandGap10,
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
                    label: _knowledgeBaseCRerankLabel(context),
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
    if (profile == null) {
      return _fullRow(
        KnowledgeDialogNotice(
          icon: Icons.hub_outlined,
          message: openHandLocalizedText(
            context,
            zh: '当前保存的嵌入模型已不可用。请重新选择一个已开启“嵌入生成”的模型。',
            zhHant: '目前儲存的嵌入模型已不可用。請重新選擇一個已啟用「嵌入生成」的模型。',
            en: 'The saved embedding model is unavailable. Choose an embedding-enabled model again.',
            fr: 'Le modèle d’embedding enregistré est indisponible. Choisissez à nouveau un modèle compatible.',
            de: 'Das gespeicherte Embedding-Modell ist nicht verfügbar. Wählen Sie erneut ein embedding-fähiges Modell.',
            ja: '保存済みの埋め込みモデルは利用できません。埋め込み対応モデルを選び直してください。',
          ),
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
        label: openHandLocalizedText(
          context,
          zh: '维度范围',
          zhHant: '維度範圍',
          en: 'Dimensions',
          fr: 'Dimensions',
          de: 'Dimensionen',
          ja: '次元範囲',
        ),
        value: dimensions,
      ),
      (
        icon: Icons.input_rounded,
        label: openHandLocalizedText(
          context,
          zh: '最大输入',
          zhHant: '最大輸入',
          en: 'Max input',
          fr: 'Entrée max',
          de: 'Max. Eingabe',
          ja: '最大入力',
        ),
        value: '${profile.embeddingMaxInputTokens ?? '-'}',
      ),
      (
        icon: Icons.batch_prediction_outlined,
        label: openHandLocalizedText(
          context,
          zh: 'Batch / 上限',
          zhHant: 'Batch / 上限',
          en: 'Batch / limit',
          fr: 'Batch / limite',
          de: 'Batch / Limit',
          ja: 'Batch / 上限',
        ),
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
        label: openHandLocalizedText(
          context,
          zh: '距离/归一化',
          zhHant: '距離/正規化',
          en: 'Metric / normalized',
          fr: 'Métrique / normalisé',
          de: 'Metrik / normalisiert',
          ja: '距離/正規化',
        ),
        value: [
          profile.embeddingSimilarityMetric ?? '-',
          _nullableBoolLabel(context, profile.embeddingOutputsNormalized),
        ].join(' / '),
      ),
    ];
    final details = <({IconData icon, String label, String value})>[
      (
        icon: Icons.route_outlined,
        label: openHandLocalizedText(
          context,
          zh: '模型路由',
          zhHant: '模型路由',
          en: 'Model routing',
          fr: 'Routage du modèle',
          de: 'Modell-Routing',
          ja: 'モデルルーティング',
        ),
        value: _listLabel(<String>[
          if (profile.embeddingQueryModelId != null)
            'query ${profile.embeddingQueryModelId}',
          if (profile.embeddingDocumentModelId != null)
            'doc ${profile.embeddingDocumentModelId}',
        ]),
      ),
      (
        icon: Icons.tune_rounded,
        label: openHandLocalizedText(
          context,
          zh: '支持参数',
          zhHant: '支援參數',
          en: 'Supported parameters',
          fr: 'Paramètres pris en charge',
          de: 'Unterstützte Parameter',
          ja: '対応パラメータ',
        ),
        value: _listLabel(profile.supportedParameters),
      ),
      (
        icon: Icons.data_object_rounded,
        label: openHandLocalizedText(
          context,
          zh: '默认参数',
          zhHant: '預設參數',
          en: 'Default parameters',
          fr: 'Paramètres par défaut',
          de: 'Standardparameter',
          ja: '既定パラメータ',
        ),
        value: _jsonMapLabel(profile.defaultParameters),
      ),
      (
        icon: Icons.swap_vert_rounded,
        label: openHandLocalizedText(
          context,
          zh: '输入类型',
          zhHant: '輸入類型',
          en: 'Input types',
          fr: 'Types d’entrée',
          de: 'Eingabetypen',
          ja: '入力タイプ',
        ),
        value: [
          _listLabel(profile.embeddingInputTypes),
          if (profile.embeddingDefaultInputType != null)
            '${_knowledgeBaseCDefaultLabel(context)} ${profile.embeddingDefaultInputType}',
          if (profile.embeddingQueryInputType != null)
            'query ${profile.embeddingQueryInputType}',
          if (profile.embeddingDocumentInputType != null)
            'doc ${profile.embeddingDocumentInputType}',
        ].join(' / '),
      ),
      (
        icon: Icons.task_alt_rounded,
        label: openHandLocalizedText(
          context,
          zh: '任务类型',
          zhHant: '任務類型',
          en: 'Task types',
          fr: 'Types de tâche',
          de: 'Aufgabentypen',
          ja: 'タスクタイプ',
        ),
        value: [
          _listLabel(profile.embeddingSupportedTaskTypes),
          if (profile.embeddingDefaultQueryTaskType != null)
            'query ${profile.embeddingDefaultQueryTaskType}',
          if (profile.embeddingDefaultDocumentTaskType != null)
            'doc ${profile.embeddingDefaultDocumentTaskType}',
          if (profile.embeddingDefaultTaskType != null)
            '${_knowledgeBaseCDefaultLabel(context)} ${profile.embeddingDefaultTaskType}',
        ].join(' / '),
      ),
      (
        icon: Icons.short_text_rounded,
        label: openHandLocalizedText(
          context,
          zh: '文本前缀',
          zhHant: '文字前綴',
          en: 'Text prefixes',
          fr: 'Préfixes texte',
          de: 'Textpräfixe',
          ja: 'テキスト接頭辞',
        ),
        value: _listLabel(<String>[
          if (profile.embeddingQueryTextPrefix != null)
            'query ${profile.embeddingQueryTextPrefix}',
          if (profile.embeddingDocumentTextPrefix != null)
            'doc ${profile.embeddingDocumentTextPrefix}',
        ]),
      ),
      (
        icon: Icons.text_fields_rounded,
        label: openHandLocalizedText(
          context,
          zh: '编码格式',
          zhHant: '編碼格式',
          en: 'Encoding formats',
          fr: 'Formats d’encodage',
          de: 'Kodierungsformate',
          ja: 'エンコード形式',
        ),
        value: [
          _listLabel(profile.embeddingEncodingFormats),
          if (profile.embeddingDefaultEncodingFormat != null)
            '${_knowledgeBaseCDefaultLabel(context)} ${profile.embeddingDefaultEncodingFormat}',
        ].join(' / '),
      ),
      (
        icon: Icons.memory_rounded,
        label: openHandLocalizedText(
          context,
          zh: '输出 dtype',
          zhHant: '輸出 dtype',
          en: 'Output dtype',
          fr: 'dtype de sortie',
          de: 'Ausgabe-dtype',
          ja: '出力 dtype',
        ),
        value: [
          _listLabel(profile.embeddingOutputDTypes),
          if (profile.embeddingDefaultOutputDType != null)
            '${_knowledgeBaseCDefaultLabel(context)} ${profile.embeddingDefaultOutputDType}',
          if (profile.embeddingDefaultTruncation != null)
            '${openHandLocalizedText(context, zh: '截断', zhHant: '截斷', en: 'truncate', fr: 'troncature', de: 'Kürzung', ja: '切り詰め')} ${profile.embeddingDefaultTruncation}',
        ].join(' / '),
      ),
    ];
    return _fullRow(
      AnimatedSize(
        duration: openHandMotionDurationMs(context, 240),
        curve: kOpenHandSwitchInCurve,
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: openHandMotionDurationMs(context, 220),
          switchInCurve: kOpenHandSwitchInCurve,
          switchOutCurve: kOpenHandSwitchOutCurve,
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
              borderRadius: kOpenHandBorderRadius16,
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
                        borderRadius: kOpenHandBorderRadius12,
                      ),
                      child: Icon(
                        Icons.analytics_outlined,
                        size: 19,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                    kOpenHandHGap10,
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            openHandLocalizedText(
                              context,
                              zh: '模型画像',
                              zhHant: '模型画像',
                              en: 'Model Profile',
                              fr: 'Profil du modèle',
                              de: 'Modellprofil',
                              ja: 'モデルプロファイル',
                            ),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          kOpenHandGap2,
                          Text(
                            trimmedNonEmptyStrings(<Object?>[
                              selectedConfig?.providerLabel,
                              _settings.modelId,
                            ]).join(' / '),
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
                    kOpenHandHGap10,
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      alignment: WrapAlignment.end,
                      children: [
                        if (profile.embeddingSupportsCustomDimensions)
                          KnowledgeDialogChip(
                            icon: Icons.open_in_full_rounded,
                            label: openHandLocalizedText(
                              context,
                              zh: '可调维度',
                              zhHant: '可調維度',
                              en: 'Custom dims',
                              fr: 'Dimensions ajustables',
                              de: 'Anpassbare Dimensionen',
                              ja: '次元調整可',
                            ),
                          ),
                        if (profile.supportsRerank)
                          KnowledgeDialogChip(
                            icon: Icons.filter_alt_rounded,
                            label: _knowledgeBaseCRerankLabel(context),
                          ),
                      ],
                    ),
                  ],
                ),
                kOpenHandGap12,
                _embeddingMetricsGrid(context, metrics),
                kOpenHandGap12,
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
        borderRadius: kOpenHandBorderRadius12,
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
              borderRadius: kOpenHandBorderRadius10,
            ),
            child: Icon(
              metric.icon,
              size: 17,
              color: colorScheme.onSecondaryContainer,
            ),
          ),
          kOpenHandHGap9,
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
                kOpenHandGap3,
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
        borderRadius: kOpenHandBorderRadius12,
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.34),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(detail.icon, size: 17, color: colorScheme.onSurfaceVariant),
          kOpenHandHGap8,
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
                kOpenHandGap3,
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
                    title: openHandLocalizedText(
                      context,
                      zh: '向量输出',
                      zhHant: '向量輸出',
                      en: 'Vector Output',
                      fr: 'Sortie vectorielle',
                      de: 'Vektorausgabe',
                      ja: 'ベクトル出力',
                    ),
                    subtitle: openHandLocalizedText(
                      context,
                      zh: '控制最终写入向量库的维度、输入预算与单批规模。',
                      zhHant: '控制最終寫入向量庫的維度、輸入預算與單批規模。',
                      en: 'Controls vector dimensions, input budget, and batch size.',
                      fr: 'Contrôle les dimensions vectorielles, le budget d’entrée et la taille de batch.',
                      de: 'Steuert Vektordimensionen, Eingabebudget und Batchgröße.',
                      ja: 'ベクトルストアへ書き込む次元、入力予算、バッチサイズを制御します。',
                    ),
                    child: _embeddingSettingsGrid(
                      context,
                      children: [
                        _embeddingSettingTextField(
                          context,
                          controller: _dimensions,
                          label: openHandLocalizedText(
                            context,
                            zh: '默认向量维度',
                            zhHant: '預設向量維度',
                            en: 'Default dimensions',
                            fr: 'Dimensions par défaut',
                            de: 'Standarddimensionen',
                            ja: '既定ベクトル次元',
                          ),
                          icon: Icons.straighten_rounded,
                        ),
                        _embeddingSettingTextField(
                          context,
                          controller: _maxInputTokens,
                          label: openHandLocalizedText(
                            context,
                            zh: '最大输入 token',
                            zhHant: '最大輸入 token',
                            en: 'Max input tokens',
                            fr: 'Tokens d’entrée max',
                            de: 'Max. Eingabetokens',
                            ja: '最大入力トークン',
                          ),
                          icon: Icons.input_rounded,
                        ),
                        _embeddingSettingTextField(
                          context,
                          controller: _batchSize,
                          label: openHandLocalizedText(
                            context,
                            zh: '批量大小',
                            zhHant: '批次大小',
                            en: 'Batch size',
                            fr: 'Taille de batch',
                            de: 'Batchgröße',
                            ja: 'バッチサイズ',
                          ),
                          icon: Icons.batch_prediction_outlined,
                        ),
                      ],
                    ),
                  ),
                  _embeddingTuningGroup(
                    context,
                    width: groupWidth,
                    icon: Icons.speed_rounded,
                    title: openHandLocalizedText(
                      context,
                      zh: '请求韧性',
                      zhHant: '請求韌性',
                      en: 'Request Resilience',
                      fr: 'Résilience des requêtes',
                      de: 'Anfrage-Resilienz',
                      ja: 'リクエスト耐性',
                    ),
                    subtitle: openHandLocalizedText(
                      context,
                      zh: '限制请求耗时、失败重试和并发，避免资源被无限占用。',
                      zhHant: '限制請求耗時、失敗重試和並發，避免資源被無限占用。',
                      en: 'Bounds timeout, retries, backoff, and concurrency.',
                      fr: 'Encadre le délai, les retries, le backoff et la concurrence.',
                      de: 'Begrenzt Timeout, Wiederholungen, Backoff und Nebenläufigkeit.',
                      ja: 'タイムアウト、再試行、バックオフ、並列数を制限し、リソース占有を防ぎます。',
                    ),
                    child: _embeddingSettingsGrid(
                      context,
                      children: [
                        _embeddingSettingTextField(
                          context,
                          controller: _timeout,
                          label: openHandLocalizedText(
                            context,
                            zh: '请求超时',
                            zhHant: '請求逾時',
                            en: 'Request timeout',
                            fr: 'Délai de requête',
                            de: 'Anfrage-Timeout',
                            ja: 'リクエストタイムアウト',
                          ),
                          icon: Icons.timer_outlined,
                          suffix: 's',
                        ),
                        _embeddingSettingTextField(
                          context,
                          controller: _retryCount,
                          label: openHandLocalizedText(
                            context,
                            zh: '失败重试',
                            zhHant: '失敗重試',
                            en: 'Retry count',
                            fr: 'Nombre de retries',
                            de: 'Wiederholungen',
                            ja: '再試行回数',
                          ),
                          icon: Icons.replay_rounded,
                        ),
                        _embeddingSettingTextField(
                          context,
                          controller: _retryBackoffMs,
                          label: openHandLocalizedText(
                            context,
                            zh: '重试退避',
                            zhHant: '重試退避',
                            en: 'Retry backoff',
                            fr: 'Backoff des retries',
                            de: 'Retry-Backoff',
                            ja: '再試行バックオフ',
                          ),
                          icon: Icons.more_time_rounded,
                          suffix: 'ms',
                        ),
                        _embeddingSettingTextField(
                          context,
                          controller: _concurrentRequests,
                          label: openHandLocalizedText(
                            context,
                            zh: '并发请求',
                            zhHant: '並發請求',
                            en: 'Concurrent requests',
                            fr: 'Requêtes concurrentes',
                            de: 'Parallele Anfragen',
                            ja: '同時リクエスト',
                          ),
                          icon: Icons.call_split_rounded,
                        ),
                      ],
                    ),
                  ),
                  _embeddingTuningGroup(
                    context,
                    width: maxWidth,
                    icon: Icons.privacy_tip_outlined,
                    title: openHandLocalizedText(
                      context,
                      zh: '隐私与缓存',
                      zhHant: '隱私與快取',
                      en: 'Privacy and Cache',
                      fr: 'Confidentialité et cache',
                      de: 'Datenschutz und Cache',
                      ja: 'プライバシーとキャッシュ',
                    ),
                    subtitle: openHandLocalizedText(
                      context,
                      zh: '云端 embedding 会发送文档 chunk 或用户 query；默认保持关闭。',
                      zhHant: '雲端 embedding 會傳送文件 chunk 或使用者 query；預設保持關閉。',
                      en: 'Cloud embeddings send document chunks or user queries; keep them off unless approved.',
                      fr: 'Les embeddings cloud envoient des chunks de document ou des requêtes utilisateur ; gardez-les désactivés sans approbation.',
                      de: 'Cloud-Embeddings senden Dokument-Chunks oder Nutzerabfragen; lassen Sie sie ohne Freigabe deaktiviert.',
                      ja: 'クラウド埋め込みはドキュメントチャンクやユーザークエリを送信します。承認がない限りオフにしてください。',
                    ),
                    child: _embeddingSettingsGrid(
                      context,
                      minItemWidth: 220,
                      children: [
                        _embeddingSwitchTile(
                          context,
                          label: openHandLocalizedText(
                            context,
                            zh: '允许发送文档内容',
                            zhHant: '允許傳送文件內容',
                            en: 'Allow document cloud embedding',
                            fr: 'Autoriser l’embedding cloud des documents',
                            de: 'Cloud-Embedding für Dokumente erlauben',
                            ja: 'ドキュメントのクラウド埋め込みを許可',
                          ),
                          subtitle: openHandLocalizedText(
                            context,
                            zh: '导入文档向量化时生效',
                            zhHant: '匯入文件向量化時生效',
                            en: 'Used while indexing documents',
                            fr: 'Utilisé lors de l’indexation des documents',
                            de: 'Wird beim Indexieren von Dokumenten genutzt',
                            ja: 'ドキュメントのインデックス作成時に使用',
                          ),
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
                          label: openHandLocalizedText(
                            context,
                            zh: '允许发送用户查询',
                            zhHant: '允許傳送使用者查詢',
                            en: 'Allow query cloud embedding',
                            fr: 'Autoriser l’embedding cloud des requêtes',
                            de: 'Cloud-Embedding für Abfragen erlauben',
                            ja: 'クエリのクラウド埋め込みを許可',
                          ),
                          subtitle: openHandLocalizedText(
                            context,
                            zh: '发送消息检索时生效',
                            zhHant: '傳送訊息檢索時生效',
                            en: 'Used while retrieving on send',
                            fr: 'Utilisé lors de la recherche à l’envoi',
                            de: 'Wird beim Abruf während des Sendens genutzt',
                            ja: '送信時の検索で使用',
                          ),
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
                          label: openHandLocalizedText(
                            context,
                            zh: '缓存查询 embedding',
                            zhHant: '快取查詢 embedding',
                            en: 'Cache query embedding',
                            fr: 'Mettre en cache l’embedding des requêtes',
                            de: 'Abfrage-Embedding cachen',
                            ja: 'クエリ埋め込みをキャッシュ',
                          ),
                          subtitle: openHandLocalizedText(
                            context,
                            zh: '复用重复查询向量',
                            zhHant: '重複使用重複查詢向量',
                            en: 'Reuses vectors for repeated queries',
                            fr: 'Réutilise les vecteurs des requêtes répétées',
                            de: 'Verwendet Vektoren für wiederholte Abfragen erneut',
                            ja: '繰り返しクエリのベクトルを再利用',
                          ),
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
          borderRadius: kOpenHandBorderRadius16,
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
                    borderRadius: kOpenHandBorderRadius10,
                  ),
                  child: Icon(icon, size: 18, color: colorScheme.primary),
                ),
                kOpenHandHGap9,
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
                      kOpenHandGap2,
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
            kOpenHandGap12,
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
      curve: kOpenHandSwitchInCurve,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color:
            (value
                    ? colorScheme.primaryContainer
                    : colorScheme.surfaceContainerHigh)
                .withValues(alpha: value ? 0.24 : 0.58),
        borderRadius: kOpenHandBorderRadius12,
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
                kOpenHandGap3,
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
          kOpenHandHGap10,
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
    return _fullRow(
      KnowledgeDialogNotice(
        icon: Icons.info_outline_rounded,
        message: openHandLocalizedText(
          context,
          zh: '没有已开启“嵌入生成”的模型。请先在设置的模型配置中启用该能力。',
          zhHant: '沒有已啟用「嵌入生成」的模型。請先在設定的模型配置中啟用該能力。',
          en: 'No model profile has Embedding Generation enabled. Enable it in model settings first.',
          fr: 'Aucun profil de modèle n’a la génération d’embedding activée. Activez-la d’abord dans les paramètres du modèle.',
          de: 'Kein Modellprofil hat Embedding-Erzeugung aktiviert. Aktivieren Sie sie zuerst in den Modelleinstellungen.',
          ja: '埋め込み生成が有効なモデルプロファイルがありません。先にモデル設定で有効にしてください。',
        ),
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.34),
        borderRadius: kOpenHandBorderRadius14,
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
              kOpenHandHGap8,
              Expanded(
                child: Text(
                  openHandLocalizedText(
                    context,
                    zh: '模型解析规则',
                    zhHant: '模型解析規則',
                    en: 'Model Parsing Rules',
                    fr: 'Règles d’analyse par modèle',
                    de: 'Modellbasierte Parsing-Regeln',
                    ja: 'モデル解析ルール',
                  ),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          kOpenHandGap6,
          Text(
            openHandLocalizedText(
              context,
              zh: '为指定源文件类型启用 reader 模型后，导入时会先转换为目标类型，再进入分块与向量化。',
              zhHant: '為指定來源檔案類型啟用 reader 模型後，匯入時會先轉換為目標類型，再進入分塊與向量化。',
              en: 'When a reader model is enabled for a source type, import converts it to the target type before chunking and embedding.',
              fr: 'Lorsqu’un modèle reader est activé pour un type source, l’import le convertit vers le type cible avant le découpage et l’embedding.',
              de: 'Wenn ein Reader-Modell für einen Quelltyp aktiviert ist, wird beim Import vor Chunking und Embedding in den Zieltyp konvertiert.',
              ja: '指定したソースファイル種別で reader モデルを有効にすると、インポート時にチャンク化と埋め込みの前に対象種別へ変換します。',
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          kOpenHandGap12,
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
              kOpenHandGap10,
          ],
          if (readerModels.isEmpty) ...[
            kOpenHandGap12,
            KnowledgeDialogNotice(
              icon: Icons.info_outline_rounded,
              message: openHandLocalizedText(
                context,
                zh: '当前没有已开启“读取转换”的模型。请先在设置的模型配置中启用该能力并配置源/目标类型。',
                zhHant: '目前沒有已啟用「讀取轉換」的模型。請先在設定的模型配置中啟用該能力並設定來源/目標類型。',
                en: 'No model profile has Read Conversion enabled. Enable it in model settings and configure source/target types first.',
                fr: 'Aucun profil de modèle n’a la conversion de lecture activée. Activez-la et configurez les types source/cible.',
                de: 'Kein Modellprofil hat Lese-Konvertierung aktiviert. Aktivieren Sie sie und konfigurieren Sie Quell-/Zieltypen.',
                ja: '読み取り変換が有効なモデルプロファイルがありません。先にモデル設定で有効化し、ソース/対象種別を設定してください。',
              ),
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
    final l10n = AppLocalizations.of(context)!;
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
        borderRadius: kOpenHandBorderRadius12,
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
                  ReaderFileType.label(sourceType, l10n),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              kOpenHandHGap12,
              SizedBox(
                width: 150,
                child: AnimatedDropdownButtonFormField<String>(
                  initialValue: rule.mode,
                  isExpanded: true,
                  decoration: knowledgeDialogInputDecoration(
                    context,
                    openHandLocalizedText(
                      context,
                      zh: '解析方式',
                      zhHant: '解析方式',
                      en: 'Parser',
                      fr: 'Analyseur',
                      de: 'Parser',
                      ja: '解析方式',
                    ),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: KnowledgeReaderParserMode.local,
                      child: Text(
                        openHandLocalizedText(
                          context,
                          zh: '本地解析',
                          zhHant: '本地解析',
                          en: 'Local',
                          fr: 'Local',
                          de: 'Lokal',
                          ja: 'ローカル解析',
                        ),
                      ),
                    ),
                    DropdownMenuItem(
                      value: KnowledgeReaderParserMode.model,
                      child: Text(
                        openHandLocalizedText(
                          context,
                          zh: '模型解析',
                          zhHant: '模型解析',
                          en: 'Model',
                          fr: 'Modèle',
                          de: 'Modell',
                          ja: 'モデル解析',
                        ),
                      ),
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
            duration: openHandMotionDuration(context, kOpenHandMotion260),
            curve: Curves.easeOutBack,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: openHandMotionDuration(context, kOpenHandMotion220),
              switchInCurve: kOpenHandSwitchInCurve,
              switchOutCurve: kOpenHandSwitchOutCurve,
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
                              message: l10n.knowledgeReaderNoModelForType(
                                ReaderFileType.label(sourceType, l10n),
                              ),
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
                              labelZhHant: 'Reader 模型',
                              labelFr: 'Modèle reader',
                              labelDe: 'Reader-Modell',
                              labelJa: 'Reader モデル',
                              helperZh: '仅显示具备“读取转换”且支持当前源文件类型的模型。',
                              helperEn:
                                  'Only read-conversion models supporting this source type are shown.',
                              helperZhHant: '僅顯示具備「讀取轉換」且支援目前來源檔案類型的模型。',
                              helperFr:
                                  'Seuls les modèles de conversion de lecture compatibles avec ce type source sont affichés.',
                              helperDe:
                                  'Es werden nur Lese-Konvertierungsmodelle angezeigt, die diesen Quelltyp unterstützen.',
                              helperJa: '現在のソースファイル種別に対応する読み取り変換モデルのみ表示します。',
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
                            kOpenHandGap10,
                            AnimatedDropdownButtonFormField<String>(
                              initialValue: safeTarget,
                              isExpanded: true,
                              decoration: knowledgeDialogInputDecoration(
                                context,
                                openHandLocalizedText(
                                  context,
                                  zh: '转换目标类型',
                                  zhHant: '轉換目標類型',
                                  en: 'Target type',
                                  fr: 'Type cible',
                                  de: 'Zieltyp',
                                  ja: '変換先の種類',
                                ),
                              ),
                              items: [
                                for (final item in safeTargetValues)
                                  DropdownMenuItem(
                                    value: item,
                                    child: Text(
                                      ReaderFileType.label(item, l10n),
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
        duration: openHandMotionDuration(context, kOpenHandMotion260,
        ),
        curve: Curves.easeOutBack,
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: openHandMotionDuration(context, kOpenHandMotion220,
          ),
          switchInCurve: kOpenHandSwitchInCurve,
          switchOutCurve: kOpenHandSwitchOutCurve,
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
            borderRadius: kOpenHandBorderRadius12,
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
                      kOpenHandGap4,
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
              kOpenHandHGap10,
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
          child: AnimatedDropdownButtonFormField<String>(
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

// 本文件内复用文案。

String _knowledgeBaseCDefaultLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '默认',
    zhHant: '預設',
    en: 'default',
    fr: 'défaut',
    de: 'Standard',
    ja: '既定',
  );
}

String _knowledgeBaseCRerankLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '可重排',
    zhHant: '可重排',
    en: 'Rerank',
    fr: 'Reclassement',
    de: 'Rerank',
    ja: '再ランク',
  );
}

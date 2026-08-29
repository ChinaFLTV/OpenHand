import 'package:flutter/material.dart';
import 'package:openhand/shared/ui/openhand_spacing.dart';

import '../../app/model/app_settings_snapshot.dart';
import '../../features/ai/model/ai_model_config.dart';
import '../util/localized_text.dart';
import 'model_search_selector.dart';
import 'openhand_tap_region.dart';

mixin OpenHandModelSelectionState<W extends StatefulWidget> on State<W> {
  String? _openHandSelectedModelConfigId;
  String? _openHandSelectedModelId;

  String? get selectedModelConfigId => _openHandSelectedModelConfigId;
  String? get selectedModelId => _openHandSelectedModelId;

  void initializeOpenHandModelSelection({
    required String? initialConfigId,
    required String? initialModelId,
    required List<AiModelConfig> availableModels,
  }) {
    _openHandSelectedModelConfigId = initialConfigId?.trim();
    _openHandSelectedModelId = initialModelId?.trim();
    if (!hasValidOpenHandModelSelection(availableModels)) {
      _openHandSelectedModelConfigId = null;
      _openHandSelectedModelId = null;
    }
  }

  bool hasValidOpenHandModelSelection(List<AiModelConfig> availableModels) {
    final configId = _openHandSelectedModelConfigId;
    final modelId = _openHandSelectedModelId;
    if (configId == null ||
        configId.isEmpty ||
        modelId == null ||
        modelId.isEmpty) {
      return false;
    }
    return availableModels.any(
      (config) => config.id == configId && config.allModelIds.contains(modelId),
    );
  }

  void selectOpenHandModel(
    (String providerConfigId, String modelId) selection,
  ) {
    setState(() {
      _openHandSelectedModelConfigId = selection.$1;
      _openHandSelectedModelId = selection.$2;
    });
  }
}

class OpenHandModelSelectorField extends StatefulWidget {
  const OpenHandModelSelectorField({
    super.key,
    required this.models,
    required this.recentSelections,
    required this.selectedConfigId,
    required this.selectedModelId,
    required this.onSelected,
    this.required = false,
    this.labelZh = '使用模型',
    this.labelEn = 'Model',
    this.labelZhHant,
    this.labelFr,
    this.labelDe,
    this.labelJa,
    this.helperZh,
    this.helperEn,
    this.helperZhHant,
    this.helperFr,
    this.helperDe,
    this.helperJa,
    this.modelFilter,
    this.borderRadius,
  });

  final List<AiModelConfig> models;
  final List<RecentModelSelection> recentSelections;
  final String? selectedConfigId;
  final String? selectedModelId;
  final ValueChanged<(String providerConfigId, String modelId)> onSelected;
  final bool required;
  final String labelZh;
  final String labelEn;
  final String? labelZhHant;
  final String? labelFr;
  final String? labelDe;
  final String? labelJa;
  final String? helperZh;
  final String? helperEn;
  final String? helperZhHant;
  final String? helperFr;
  final String? helperDe;
  final String? helperJa;
  final bool Function(AiModelConfig config, String modelId)? modelFilter;
  final BorderRadius? borderRadius;

  @override
  State<OpenHandModelSelectorField> createState() =>
      _OpenHandModelSelectorFieldState();
}

class _OpenHandModelSelectorFieldState
    extends State<OpenHandModelSelectorField> {
  bool _menuOpen = false;

  bool get _hasModels {
    return widget.models.any(
      (item) => item.allModelIds.any(
        (modelId) =>
            widget.modelFilter == null ||
            widget.modelFilter!(item, modelId.trim()),
      ),
    );
  }

  bool get hasValidSelection {
    final configId = widget.selectedConfigId?.trim();
    final modelId = widget.selectedModelId?.trim();
    if (configId == null ||
        configId.isEmpty ||
        modelId == null ||
        modelId.isEmpty) {
      return false;
    }
    return widget.models.any((config) {
      if (config.id != configId || !config.allModelIds.contains(modelId)) {
        return false;
      }
      return widget.modelFilter == null || widget.modelFilter!(config, modelId);
    });
  }

  String? _selectedDisplayLabel() {
    final configId = widget.selectedConfigId?.trim();
    final modelId = widget.selectedModelId?.trim();
    if (configId == null || configId.isEmpty) return null;
    final config = widget.models
        .where((item) => item.id == configId)
        .firstOrNull;
    if (config == null) return null;
    if (modelId != null && modelId.isNotEmpty) return modelId;
    if (config.modelId.trim().isNotEmpty) return config.modelId.trim();
    return config.providerLabel;
  }

  Future<void> _showModelMenu() async {
    if (_menuOpen || !_hasModels) return;
    setState(() => _menuOpen = true);
    final value = await showModelSearchSelector(
      context: context,
      models: widget.models,
      recentSelections: widget.recentSelections,
      selectedConfigId: widget.selectedConfigId,
      selectedModelId: widget.selectedModelId,
      modelFilter: widget.modelFilter,
    );
    if (!mounted) return;
    setState(() => _menuOpen = false);
    if (value != null) {
      widget.onSelected((value.$1, value.$2));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final borderRadius = widget.borderRadius;
    final usesDefaultLabel =
        widget.labelZh == '使用模型' && widget.labelEn == 'Model';
    final labelZhHant = widget.labelZhHant ?? widget.labelZh;
    final labelFr =
        widget.labelFr ?? (usesDefaultLabel ? 'Modèle' : widget.labelEn);
    final labelDe =
        widget.labelDe ?? (usesDefaultLabel ? 'Modell' : widget.labelEn);
    final labelJa =
        widget.labelJa ?? (usesDefaultLabel ? 'モデル' : widget.labelEn);
    final label = openHandLocalizedText(
      context,
      zh: widget.required ? '${widget.labelZh} *' : widget.labelZh,
      en: widget.required ? '${widget.labelEn} *' : widget.labelEn,
      zhHant: widget.required ? '$labelZhHant *' : labelZhHant,
      fr: widget.required ? '$labelFr *' : labelFr,
      de: widget.required ? '$labelDe *' : labelDe,
      ja: widget.required ? '$labelJa *' : labelJa,
    );
    final displayLabel = _selectedDisplayLabel();
    final placeholder = openHandLocalizedText(
      context,
      zh: _hasModels ? '点击选择模型' : '未配置可用模型',
      en: _hasModels ? 'Tap to choose a model' : 'No models configured',
      zhHant: _hasModels ? '點擊選擇模型' : '未設定可用模型',
      fr: _hasModels
          ? 'Touchez pour choisir un modèle'
          : 'Aucun modèle configuré',
      de: _hasModels ? 'Modell auswählen' : 'Keine Modelle konfiguriert',
      ja: _hasModels ? 'モデルを選択' : '利用可能なモデルが未設定です',
    );
    final helper = openHandLocalizedText(
      context,
      zh:
          widget.helperZh ??
          (widget.required
              ? '此模板创建后会自动发送首条消息，请先指定本次会话使用的模型。'
              : '仅影响本次新建会话；未选择时沿用当前激活模型。'),
      en:
          widget.helperEn ??
          (widget.required
              ? 'This template sends the first message automatically, so choose the model before creating it.'
              : 'Applies only to this new session; otherwise the active model is kept.'),
      zhHant:
          widget.helperZhHant ??
          widget.helperZh ??
          (widget.required
              ? '此範本建立後會自動傳送第一則訊息，請先指定本次會話使用的模型。'
              : '僅影響本次新建會話；未選擇時沿用目前啟用模型。'),
      fr:
          widget.helperFr ??
          widget.helperEn ??
          (widget.required
              ? 'Ce modèle envoie automatiquement le premier message ; choisissez le modèle avant de le créer.'
              : 'S’applique uniquement à cette nouvelle session ; sinon le modèle actif est conservé.'),
      de:
          widget.helperDe ??
          widget.helperEn ??
          (widget.required
              ? 'Diese Vorlage sendet die erste Nachricht automatisch. Wählen Sie vorher das Modell.'
              : 'Gilt nur für diese neue Sitzung; sonst bleibt das aktive Modell erhalten.'),
      ja:
          widget.helperJa ??
          widget.helperEn ??
          (widget.required
              ? 'このテンプレートは最初のメッセージを自動送信します。作成前にモデルを選択してください。'
              : 'この新規セッションにのみ適用されます。未選択の場合は現在の有効モデルを使います。'),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OpenHandTapRegion(
          onTap: _hasModels ? _showModelMenu : null,
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: label,
              border: borderRadius == null
                  ? const OutlineInputBorder()
                  : OutlineInputBorder(borderRadius: borderRadius),
              enabledBorder: borderRadius == null
                  ? null
                  : OutlineInputBorder(borderRadius: borderRadius),
              focusedBorder: borderRadius == null
                  ? null
                  : OutlineInputBorder(borderRadius: borderRadius),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              suffixIcon: Icon(
                _menuOpen
                    ? Icons.arrow_drop_up_rounded
                    : Icons.arrow_drop_down_rounded,
                size: 20,
                color: _hasModels
                    ? cs.onSurfaceVariant
                    : cs.onSurfaceVariant.withValues(alpha: 0.55),
              ),
              suffixIconConstraints: const BoxConstraints(
                minWidth: 28,
                minHeight: 28,
              ),
            ),
            child: Text(
              displayLabel ?? placeholder,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: _hasModels ? cs.onSurface : cs.onSurfaceVariant,
              ),
            ),
          ),
        ),
        kOpenHandGap6,
        Text(
          helper,
          style: theme.textTheme.bodySmall?.copyWith(
            color: hasValidSelection || !widget.required
                ? cs.onSurfaceVariant
                : cs.error,
          ),
        ),
      ],
    );
  }
}

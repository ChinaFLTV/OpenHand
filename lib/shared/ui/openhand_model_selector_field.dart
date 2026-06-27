import 'package:flutter/material.dart';

import '../../app/model/app_settings_snapshot.dart';
import '../../features/ai/model/ai_model_config.dart';
import '../util/localized_text.dart';
import 'model_search_selector.dart';

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
    this.helperZh,
    this.helperEn,
    this.modelFilter,
  });

  final List<AiModelConfig> models;
  final List<RecentModelSelection> recentSelections;
  final String? selectedConfigId;
  final String? selectedModelId;
  final ValueChanged<(String providerConfigId, String modelId)> onSelected;
  final bool required;
  final String labelZh;
  final String labelEn;
  final String? helperZh;
  final String? helperEn;
  final bool Function(AiModelConfig config, String modelId)? modelFilter;

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
    final label = openHandLocalizedText(
      context,
      zh: widget.required ? '${widget.labelZh} *' : widget.labelZh,
      en: widget.required ? '${widget.labelEn} *' : widget.labelEn,
    );
    final displayLabel = _selectedDisplayLabel();
    final placeholder = openHandLocalizedText(
      context,
      zh: _hasModels ? '点击选择模型' : '未配置可用模型',
      en: _hasModels ? 'Tap to choose a model' : 'No models configured',
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
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: _hasModels ? _showModelMenu : null,
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
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
        const SizedBox(height: 6),
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

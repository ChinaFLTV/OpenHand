import 'package:flutter/material.dart';

import '../../../app/model/app_settings_snapshot.dart'
    show RecentModelSelection;
import '../../../shared/ui/animated_menu.dart';
import '../../../shared/ui/motion_durations.dart';
import '../../../shared/ui/motion_preference.dart';
import '../../../shared/ui/openhand_form_fields.dart';
import '../../../shared/ui/openhand_model_selector_field.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../../ai/index.dart'
    show AiModelConfig, AiReasoningEffortOption, AiThreadTemplate;
import '../../instructions/index.dart' show UserInstructionEntry;
import '../../knowledge_base/index.dart' show KnowledgeSource;
import '../../mcp/index.dart' show McpServer;
import '../../memory/index.dart' show UserMemoryEntry;
import '../../skills/index.dart' show LocalSkill;
import '../model/workflow_definition.dart';

const double _formControlHeight = 52;

class WorkflowEditorCatalog {
  const WorkflowEditorCatalog({
    required this.models,
    required this.recentModelSelections,
    required this.templates,
    required this.skills,
    required this.memories,
    required this.instructions,
    required this.knowledgeSources,
    required this.mcpServers,
  });

  final List<AiModelConfig> models;
  final List<RecentModelSelection> recentModelSelections;
  final List<AiThreadTemplate> templates;
  final List<LocalSkill> skills;
  final List<UserMemoryEntry> memories;
  final List<UserInstructionEntry> instructions;
  final List<KnowledgeSource> knowledgeSources;
  final List<McpServer> mcpServers;
}

class WorkflowNodeConfigurationPanel extends StatelessWidget {
  const WorkflowNodeConfigurationPanel({
    super.key,
    required this.node,
    required this.catalog,
    required this.onChanged,
    required this.onClose,
    required this.onDelete,
    required this.onTest,
    required this.testing,
    this.testResult,
    this.testError,
  });

  final WorkflowNode node;
  final WorkflowEditorCatalog catalog;
  final ValueChanged<WorkflowNode> onChanged;
  final VoidCallback onClose;
  final VoidCallback onDelete;
  final VoidCallback onTest;
  final bool testing;
  final String? testResult;
  final String? testError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        children: [
          _buildHeader(context),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
              children: [
                _buildCommonTitle(context),
                kOpenHandGap14,
                switch (node.kind) {
                  WorkflowNodeKind.llm => _buildLlm(context),
                  WorkflowNodeKind.httpRequest => _buildHttp(context),
                  WorkflowNodeKind.condition => _buildCondition(context),
                  WorkflowNodeKind.loop => _buildLoop(context),
                  WorkflowNodeKind.iteration => _buildIteration(context),
                },
                if (testResult != null || testError != null) ...[
                  kOpenHandGap16,
                  _ExecutionResultCard(result: testResult, error: testError),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final descriptor = workflowNodeDescriptor(node.kind, theme.colorScheme);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 10, 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: descriptor.color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(kOpenHandRadius10),
            ),
            child: Icon(descriptor.icon, color: descriptor.color, size: 20),
          ),
          kOpenHandHGap10,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  descriptor.label,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  descriptor.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '删除节点',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
          kOpenHandHGap6,
          IconButton(
            tooltip: '关闭配置',
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildCommonTitle(BuildContext context) {
    return _FormSection(
      title: '基本信息',
      icon: Icons.badge_outlined,
      child: _LabeledField(
        label: '节点名称',
        child: TextFormField(
          key: ValueKey('title-${node.id}'),
          initialValue: node.title,
          maxLength: 60,
          buildCounter: openHandHiddenTextFieldCounter,
          decoration: _inputDecoration('输入便于识别的节点名称'),
          onChanged: (value) => onChanged(node.copyWith(title: value)),
        ),
      ),
    );
  }

  Widget _buildLlm(BuildContext context) {
    final selectedConfigId = node.stringSetting(
      WorkflowSettingKeys.modelConfigId,
    );
    final selectedProvider = catalog.models
        .where((item) => item.id == selectedConfigId)
        .firstOrNull;
    final storedModelId = node.stringSetting(WorkflowSettingKeys.modelId);
    final selectedModelId =
        selectedProvider?.allModelIds.contains(storedModelId) == true
        ? storedModelId
        : selectedProvider?.modelId ??
              selectedProvider?.allModelIds.firstOrNull;
    final selectedModel = selectedProvider == null || selectedModelId == null
        ? null
        : selectedProvider.copyWith(modelId: selectedModelId);
    final reasoningOptions =
        selectedModel?.resolvedReasoningEffortControlEnabled == true
        ? selectedModel!.resolvedReasoningEffortOptions
              .where((option) => option.isSelectable)
              .toList(growable: false)
        : const <AiReasoningEffortOption>[];
    final storedReasoningEffort = node.stringSetting(
      WorkflowSettingKeys.reasoningEffort,
    );
    final reasoningEffort =
        reasoningOptions.any((option) => option.value == storedReasoningEffort)
        ? storedReasoningEffort
        : selectedModel?.resolvedReasoningEffort;
    final selectedTemplate = node.stringSetting(WorkflowSettingKeys.templateId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FormSection(
          title: '模型与提示词',
          icon: Icons.auto_awesome_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OpenHandModelSelectorField(
                models: catalog.models,
                recentSelections: catalog.recentModelSelections,
                selectedConfigId: selectedConfigId,
                selectedModelId: selectedModelId,
                required: true,
                labelZh: '模型',
                helperZh: '选择此节点实际调用的模型。',
                helperEn: 'Choose the model used by this node.',
                borderRadius: kOpenHandBorderRadius12,
                onSelected: _setModelSelection,
              ),
              kOpenHandGap12,
              _LabeledField(
                label: '推理强度',
                helper: reasoningOptions.isEmpty
                    ? '当前模型不支持推理强度配置。'
                    : '仅影响当前工作流节点。',
                child: AnimatedDropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: reasoningEffort,
                  decoration: _inputDecoration(
                    reasoningOptions.isEmpty ? '不可配置' : '选择推理强度',
                  ),
                  items: reasoningOptions
                      .map(
                        (option) => DropdownMenuItem<String>(
                          value: option.value,
                          child: Text(
                            option.labelForLocaleName(
                              Localizations.localeOf(context).toLanguageTag(),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: reasoningOptions.isEmpty
                      ? null
                      : (value) => _set(
                          WorkflowSettingKeys.reasoningEffort,
                          value ?? '',
                        ),
                ),
              ),
              kOpenHandGap12,
              _LabeledField(
                label: '提示词模板',
                child: AnimatedDropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue:
                      catalog.templates.any(
                        (item) => item.id == selectedTemplate,
                      )
                      ? selectedTemplate
                      : catalog.templates.firstOrNull?.id,
                  decoration: _inputDecoration('选择内置提示词模板'),
                  items: catalog.templates
                      .map(
                        (template) => DropdownMenuItem<String>(
                          value: template.id,
                          child: Text(
                            template.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) =>
                      _set(WorkflowSettingKeys.templateId, value ?? ''),
                ),
              ),
              kOpenHandGap12,
              _LabeledField(
                label: '提示词',
                required: true,
                helper: '使用 {{变量名}} 引用工作流输入或上游输出。',
                child: TextFormField(
                  key: ValueKey('prompt-${node.id}'),
                  initialValue: node.stringSetting(WorkflowSettingKeys.prompt),
                  minLines: 5,
                  maxLines: 12,
                  decoration: _inputDecoration('描述任务、输入与约束'),
                  onChanged: (value) => _set(WorkflowSettingKeys.prompt, value),
                ),
              ),
            ],
          ),
        ),
        kOpenHandGap14,
        _ResourceSection(
          title: '多模态能力',
          icon: Icons.perm_media_outlined,
          options: const <_ResourceOption>[
            _ResourceOption('vision', '图片理解'),
            _ResourceOption('audio', '音频理解'),
            _ResourceOption('video', '视频理解'),
            _ResourceOption('files', '文件理解'),
          ],
          selected: node.stringSetSetting(
            WorkflowSettingKeys.multimodalCapabilities,
          ),
          onChanged: (value) =>
              _setStringSet(WorkflowSettingKeys.multimodalCapabilities, value),
        ),
        kOpenHandGap12,
        _ResourceSection(
          title: '技能',
          icon: Icons.extension_outlined,
          options: catalog.skills
              .map(
                (item) =>
                    _ResourceOption(item.name, item.name, item.description),
              )
              .toList(growable: false),
          selected: node.stringSetSetting(WorkflowSettingKeys.skillNames),
          onChanged: (value) =>
              _setStringSet(WorkflowSettingKeys.skillNames, value),
        ),
        kOpenHandGap12,
        _ResourceSection(
          title: '记忆',
          icon: Icons.psychology_alt_outlined,
          options: catalog.memories
              .map(
                (item) =>
                    _ResourceOption(item.id, item.displayTitle, item.preview),
              )
              .toList(growable: false),
          selected: node.stringSetSetting(WorkflowSettingKeys.memoryIds),
          onChanged: (value) =>
              _setStringSet(WorkflowSettingKeys.memoryIds, value),
        ),
        kOpenHandGap12,
        _ResourceSection(
          title: '指令',
          icon: Icons.rule_folder_outlined,
          options: catalog.instructions
              .where((item) => item.enabled)
              .map(
                (item) => _ResourceOption(item.id, item.name, item.description),
              )
              .toList(growable: false),
          selected: node.stringSetSetting(WorkflowSettingKeys.instructionIds),
          onChanged: (value) =>
              _setStringSet(WorkflowSettingKeys.instructionIds, value),
        ),
        kOpenHandGap12,
        _ResourceSection(
          title: '知识库',
          icon: Icons.local_library_outlined,
          options: catalog.knowledgeSources
              .map(
                (item) =>
                    _ResourceOption(item.id, item.title, item.originalPath),
              )
              .toList(growable: false),
          selected: node.stringSetSetting(
            WorkflowSettingKeys.knowledgeSourceIds,
          ),
          onChanged: (value) =>
              _setStringSet(WorkflowSettingKeys.knowledgeSourceIds, value),
        ),
        kOpenHandGap12,
        _ResourceSection(
          title: 'MCP 服务',
          icon: Icons.hub_outlined,
          options: catalog.mcpServers
              .where((item) => item.enabled)
              .map(
                (item) => _ResourceOption(item.name, item.name, item.summary),
              )
              .toList(growable: false),
          selected: node.stringSetSetting(WorkflowSettingKeys.mcpServerNames),
          onChanged: (value) =>
              _setStringSet(WorkflowSettingKeys.mcpServerNames, value),
        ),
        kOpenHandGap14,
        _buildOutputSection(context),
        kOpenHandGap14,
        _buildRetrySection(context),
        kOpenHandGap16,
        _buildTestButton(),
      ],
    );
  }

  void _setModelSelection((String, String) selection) {
    final selectedModel = catalog.models
        .where((item) => item.id == selection.$1)
        .firstOrNull
        ?.copyWith(modelId: selection.$2);
    onChanged(
      node.copyWith(
        settings: <String, Object?>{
          ...node.settings,
          WorkflowSettingKeys.modelConfigId: selection.$1,
          WorkflowSettingKeys.modelId: selection.$2,
          WorkflowSettingKeys.reasoningEffort:
              selectedModel?.resolvedReasoningEffort ?? '',
        },
      ),
    );
  }

  Widget _buildHttp(BuildContext context) {
    final method = node.stringSetting(WorkflowSettingKeys.method, 'GET');
    final bodyVisible = !const <String>{'GET', 'HEAD'}.contains(method);
    final bodyFormat = WorkflowHttpBodyFormat.fromStorage(
      node.settings[WorkflowSettingKeys.bodyFormat],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FormSection(
          title: '请求设置',
          icon: Icons.language_rounded,
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 120,
                    child: _LabeledField(
                      label: '方式',
                      child: AnimatedDropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: method,
                        decoration: _inputDecoration('方式'),
                        items:
                            const <String>[
                                  'GET',
                                  'POST',
                                  'PUT',
                                  'PATCH',
                                  'DELETE',
                                  'HEAD',
                                ]
                                .map(
                                  (item) => DropdownMenuItem<String>(
                                    value: item,
                                    child: Text(item),
                                  ),
                                )
                                .toList(growable: false),
                        onChanged: (value) =>
                            _set(WorkflowSettingKeys.method, value ?? 'GET'),
                      ),
                    ),
                  ),
                  kOpenHandHGap10,
                  Expanded(
                    child: _LabeledField(
                      label: '请求 URL',
                      required: true,
                      child: TextFormField(
                        key: ValueKey('url-${node.id}'),
                        initialValue: node.stringSetting(
                          WorkflowSettingKeys.url,
                        ),
                        decoration: _inputDecoration(
                          'https://api.example.com/v1/data',
                        ),
                        onChanged: (value) =>
                            _set(WorkflowSettingKeys.url, value),
                      ),
                    ),
                  ),
                ],
              ),
              kOpenHandGap14,
              _KeyValueEditor(
                title: '请求头',
                addLabel: '添加请求头',
                entries: node.keyValueSetting(WorkflowSettingKeys.headers),
                onChanged: (value) =>
                    _setKeyValues(WorkflowSettingKeys.headers, value),
              ),
              kOpenHandGap14,
              _KeyValueEditor(
                title: '请求参数',
                addLabel: '添加请求参数',
                entries: node.keyValueSetting(
                  WorkflowSettingKeys.queryParameters,
                ),
                onChanged: (value) =>
                    _setKeyValues(WorkflowSettingKeys.queryParameters, value),
              ),
              AnimatedSize(
                duration: openHandMotionDuration(context, kOpenHandMotion220),
                curve: Curves.easeOutCubic,
                child: bodyVisible
                    ? Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: Column(
                          children: [
                            _LabeledField(
                              label: '请求体格式',
                              child:
                                  AnimatedDropdownButtonFormField<
                                    WorkflowHttpBodyFormat
                                  >(
                                    isExpanded: true,
                                    initialValue: bodyFormat,
                                    decoration: _inputDecoration('选择请求体格式'),
                                    items: WorkflowHttpBodyFormat.values
                                        .map(
                                          (item) =>
                                              DropdownMenuItem<
                                                WorkflowHttpBodyFormat
                                              >(
                                                value: item,
                                                child: Text(
                                                  _bodyFormatLabel(item),
                                                ),
                                              ),
                                        )
                                        .toList(growable: false),
                                    onChanged: (value) => _set(
                                      WorkflowSettingKeys.bodyFormat,
                                      (value ?? WorkflowHttpBodyFormat.none)
                                          .storageValue,
                                    ),
                                  ),
                            ),
                            if (const <WorkflowHttpBodyFormat>{
                              WorkflowHttpBodyFormat.formData,
                              WorkflowHttpBodyFormat.formUrlEncoded,
                            }.contains(bodyFormat)) ...[
                              kOpenHandGap12,
                              _KeyValueEditor(
                                title: '请求体字段',
                                addLabel: '添加字段',
                                entries: node.keyValueSetting(
                                  WorkflowSettingKeys.bodyEntries,
                                ),
                                onChanged: (value) => _setKeyValues(
                                  WorkflowSettingKeys.bodyEntries,
                                  value,
                                ),
                              ),
                            ] else if (bodyFormat !=
                                WorkflowHttpBodyFormat.none) ...[
                              kOpenHandGap12,
                              _LabeledField(
                                label: '请求体',
                                helper:
                                    bodyFormat == WorkflowHttpBodyFormat.json
                                    ? '发送前会校验 JSON 格式。'
                                    : null,
                                child: TextFormField(
                                  key: ValueKey(
                                    'body-${node.id}-${bodyFormat.name}',
                                  ),
                                  initialValue: node.stringSetting(
                                    WorkflowSettingKeys.body,
                                  ),
                                  minLines: 4,
                                  maxLines: 10,
                                  decoration: _inputDecoration(
                                    bodyFormat == WorkflowHttpBodyFormat.json
                                        ? '{\n  "key": "{{value}}"\n}'
                                        : '输入请求体内容',
                                  ),
                                  onChanged: (value) =>
                                      _set(WorkflowSettingKeys.body, value),
                                ),
                              ),
                            ],
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
        kOpenHandGap14,
        _FormSection(
          title: '超时与重试',
          icon: Icons.timer_outlined,
          child: Column(
            children: [
              _NumberFieldRow(
                leftLabel: '连接超时（秒）',
                leftValue: node.intSetting(
                  WorkflowSettingKeys.connectTimeoutSeconds,
                  15,
                ),
                leftMin: 1,
                leftMax: 120,
                onLeftChanged: (value) =>
                    _set(WorkflowSettingKeys.connectTimeoutSeconds, value),
                rightLabel: '响应超时（秒）',
                rightValue: node.intSetting(
                  WorkflowSettingKeys.responseTimeoutSeconds,
                  60,
                ),
                rightMin: 1,
                rightMax: 600,
                onRightChanged: (value) =>
                    _set(WorkflowSettingKeys.responseTimeoutSeconds, value),
              ),
              kOpenHandGap12,
              _retryFields(),
            ],
          ),
        ),
        kOpenHandGap14,
        _buildOutputSection(context),
        kOpenHandGap16,
        _buildTestButton(),
      ],
    );
  }

  Widget _buildCondition(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FormSection(
          title: '分支条件',
          icon: Icons.call_split_rounded,
          child: _LabeledField(
            label: '条件表达式',
            required: true,
            helper: '支持 ==、!=、>、<、>=、<=、contains，可使用 {{变量名}}。',
            child: TextFormField(
              key: ValueKey('condition-${node.id}'),
              initialValue: node.stringSetting(WorkflowSettingKeys.expression),
              decoration: _inputDecoration('{{status}} == success'),
              onChanged: (value) => _set(WorkflowSettingKeys.expression, value),
            ),
          ),
        ),
        kOpenHandGap16,
        _buildTestButton(),
      ],
    );
  }

  Widget _buildLoop(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FormSection(
          title: '循环设置',
          icon: Icons.loop_rounded,
          child: _LabeledField(
            label: '最大循环次数',
            helper: '限制为 1–1000 次，避免无限循环。',
            child: TextFormField(
              key: ValueKey('loop-${node.id}'),
              initialValue:
                  '${node.intSetting(WorkflowSettingKeys.maxIterations, 10)}',
              keyboardType: TextInputType.number,
              decoration: _inputDecoration('10'),
              onChanged: (value) {
                final parsed = int.tryParse(value);
                if (parsed != null) {
                  _set(
                    WorkflowSettingKeys.maxIterations,
                    parsed.clamp(1, 1000),
                  );
                }
              },
            ),
          ),
        ),
        kOpenHandGap16,
        _buildTestButton(),
      ],
    );
  }

  Widget _buildIteration(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FormSection(
          title: '迭代设置',
          icon: Icons.view_week_outlined,
          child: _LabeledField(
            label: '数组变量名',
            required: true,
            helper: '最多处理前 1000 项。',
            child: TextFormField(
              key: ValueKey('iteration-${node.id}'),
              initialValue: node.stringSetting(
                WorkflowSettingKeys.iterationInput,
              ),
              decoration: _inputDecoration('items'),
              onChanged: (value) =>
                  _set(WorkflowSettingKeys.iterationInput, value),
            ),
          ),
        ),
        kOpenHandGap16,
        _buildTestButton(),
      ],
    );
  }

  Widget _buildRetrySection(BuildContext context) {
    return _FormSection(
      title: '失败重试',
      icon: Icons.replay_circle_filled_outlined,
      child: _retryFields(),
    );
  }

  Widget _retryFields() {
    return _NumberFieldRow(
      leftLabel: '重试次数',
      leftValue: node.intSetting(WorkflowSettingKeys.retryCount, 0),
      leftMin: 0,
      leftMax: 10,
      onLeftChanged: (value) => _set(WorkflowSettingKeys.retryCount, value),
      rightLabel: '重试间隔（毫秒）',
      rightValue: node.intSetting(WorkflowSettingKeys.retryIntervalMs, 1000),
      rightMin: 0,
      rightMax: 60000,
      onRightChanged: (value) =>
          _set(WorkflowSettingKeys.retryIntervalMs, value),
    );
  }

  Widget _buildOutputSection(BuildContext context) {
    final enabled = node.boolSetting(WorkflowSettingKeys.structuredOutput);
    final fields = node.outputFields();
    return _FormSection(
      title: '响应输出',
      icon: Icons.data_object_rounded,
      trailing: Switch(
        value: enabled,
        onChanged: (value) => _set(WorkflowSettingKeys.structuredOutput, value),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            enabled ? '按参数定义生成并校验结构化结果；解析失败会使节点执行失败。' : '关闭时保留节点原始响应。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          AnimatedSize(
            duration: openHandMotionDuration(context, kOpenHandMotion220),
            curve: Curves.easeOutCubic,
            child: enabled
                ? Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _OutputFieldEditor(
                      fields: fields,
                      onChanged: (value) => _set(
                        WorkflowSettingKeys.outputFields,
                        value
                            .map((item) => item.toJson())
                            .toList(growable: false),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildTestButton() {
    return FilledButton.tonalIcon(
      onPressed: testing ? null : onTest,
      icon: testing
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.play_arrow_rounded),
      label: Text(testing ? '正在测试' : '测试当前节点'),
    );
  }

  void _set(String key, Object? value) =>
      onChanged(node.withSetting(key, value));

  void _setStringSet(String key, Set<String> value) {
    final sorted = value.toList()..sort();
    _set(key, sorted);
  }

  void _setKeyValues(String key, List<WorkflowKeyValueEntry> entries) {
    _set(key, entries.map((item) => item.toJson()).toList(growable: false));
  }
}

class _FormSection extends StatelessWidget {
  const _FormSection({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(kOpenHandRadius16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: theme.colorScheme.primary),
              kOpenHandHGap8,
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          kOpenHandGap12,
          child,
        ],
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.child,
    this.helper,
    this.required = false,
  });

  final String label;
  final Widget child;
  final String? helper;
  final bool required;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: OpenHandFormLabel(label)),
            if (required)
              Text(
                ' *',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
          ],
        ),
        kOpenHandGap7,
        child,
        if (helper != null) ...[
          kOpenHandGap5,
          Text(
            helper!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _ResourceOption {
  const _ResourceOption(this.id, this.label, [this.description = '']);

  final String id;
  final String label;
  final String description;
}

class _ResourceSection extends StatelessWidget {
  const _ResourceSection({
    required this.title,
    required this.icon,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final String title;
  final IconData icon;
  final List<_ResourceOption> options;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final validSelected = selected
        .where((id) => options.any((item) => item.id == id))
        .toSet();
    return Theme(
      data: theme.copyWith(
        splashFactory: NoSplash.splashFactory,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(kOpenHandRadius14),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          leading: Icon(icon, size: 19, color: theme.colorScheme.primary),
          title: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          subtitle: Text(
            options.isEmpty
                ? '暂无可用项'
                : '已选择 ${validSelected.length} / ${options.length}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          children: [
            if (options.isEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '请先在对应板块添加资源。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: options
                      .map(
                        (option) => Tooltip(
                          message: option.description.trim().isEmpty
                              ? option.label
                              : option.description,
                          child: FilterChip(
                            label: Text(
                              option.label,
                              overflow: TextOverflow.ellipsis,
                            ),
                            selected: validSelected.contains(option.id),
                            showCheckmark: false,
                            onSelected: (enabled) {
                              final next = <String>{...validSelected};
                              enabled
                                  ? next.add(option.id)
                                  : next.remove(option.id);
                              onChanged(next);
                            },
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _KeyValueEditor extends StatelessWidget {
  const _KeyValueEditor({
    required this.title,
    required this.addLabel,
    required this.entries,
    required this.onChanged,
  });

  final String title;
  final String addLabel;
  final List<WorkflowKeyValueEntry> entries;
  final ValueChanged<List<WorkflowKeyValueEntry>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: OpenHandFormLabel(title)),
            TextButton.icon(
              onPressed: () => onChanged(<WorkflowKeyValueEntry>[
                ...entries,
                WorkflowKeyValueEntry(
                  id: 'kv-${DateTime.now().microsecondsSinceEpoch}',
                ),
              ]),
              icon: const Icon(Icons.add_rounded, size: 17),
              label: Text(addLabel),
            ),
          ],
        ),
        if (entries.isNotEmpty)
          ...entries.map((entry) {
            final index = entries.indexOf(entry);
            return Padding(
              key: ValueKey(entry.id),
              padding: EdgeInsets.only(top: index == 0 ? 12 : 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 34,
                    child: Checkbox(
                      value: entry.enabled,
                      onChanged: (value) =>
                          _replaceEntry(entry.copyWith(enabled: value ?? true)),
                    ),
                  ),
                  Expanded(
                    child: TextFormField(
                      initialValue: entry.key,
                      decoration: _inputDecoration('键'),
                      onChanged: (value) =>
                          _replaceEntry(entry.copyWith(key: value)),
                    ),
                  ),
                  kOpenHandHGap8,
                  Expanded(
                    child: TextFormField(
                      initialValue: entry.value,
                      decoration: _inputDecoration('值'),
                      onChanged: (value) =>
                          _replaceEntry(entry.copyWith(value: value)),
                    ),
                  ),
                  kOpenHandHGap4,
                  IconButton(
                    tooltip: '移除',
                    onPressed: () => onChanged(
                      entries
                          .where((item) => item.id != entry.id)
                          .toList(growable: false),
                    ),
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  void _replaceEntry(WorkflowKeyValueEntry updated) {
    onChanged(
      entries
          .map((entry) => entry.id == updated.id ? updated : entry)
          .toList(growable: false),
    );
  }
}

class _OutputFieldEditor extends StatelessWidget {
  const _OutputFieldEditor({required this.fields, required this.onChanged});

  final List<WorkflowOutputField> fields;
  final ValueChanged<List<WorkflowOutputField>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (fields.isNotEmpty)
          ...fields.map(
            (field) => _OutputFieldCard(
              key: ValueKey(field.id),
              field: field,
              onChanged: (updated) => onChanged(
                fields
                    .map((item) => item.id == updated.id ? updated : item)
                    .toList(growable: false),
              ),
              onDelete: () => onChanged(
                fields
                    .where((item) => item.id != field.id)
                    .toList(growable: false),
              ),
            ),
          ),
        kOpenHandGap10,
        OutlinedButton.icon(
          onPressed: () => onChanged(<WorkflowOutputField>[
            ...fields,
            WorkflowOutputField(
              id: 'output-${DateTime.now().microsecondsSinceEpoch}',
            ),
          ]),
          icon: const Icon(Icons.add_rounded),
          label: const Text('添加输出参数'),
        ),
      ],
    );
  }
}

class _OutputFieldCard extends StatelessWidget {
  const _OutputFieldCard({
    super.key,
    required this.field,
    required this.onChanged,
    required this.onDelete,
  });

  final WorkflowOutputField field;
  final ValueChanged<WorkflowOutputField> onChanged;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        children: [
          SizedBox(
            height: _formControlHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: field.name,
                    decoration: _inputDecoration('参数名称'),
                    onChanged: (value) =>
                        onChanged(field.copyWith(name: value)),
                  ),
                ),
                kOpenHandHGap8,
                SizedBox(
                  width: 122,
                  child: AnimatedDropdownButtonFormField<WorkflowOutputType>(
                    isExpanded: true,
                    initialValue: field.type,
                    decoration: _inputDecoration('类型'),
                    items: WorkflowOutputType.values
                        .map(
                          (type) => DropdownMenuItem<WorkflowOutputType>(
                            value: type,
                            child: Text(type.storageValue),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) => onChanged(
                      field.copyWith(type: value ?? WorkflowOutputType.string),
                    ),
                  ),
                ),
                kOpenHandHGap8,
                IconButton.filledTonal(
                  tooltip: '删除参数',
                  onPressed: onDelete,
                  style: IconButton.styleFrom(
                    fixedSize: const Size.square(_formControlHeight),
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(kOpenHandRadius12),
                    ),
                    shadowColor: Colors.transparent,
                  ),
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                ),
              ],
            ),
          ),
          kOpenHandGap8,
          SizedBox(
            height: _formControlHeight,
            child: TextFormField(
              initialValue: field.description,
              decoration: _inputDecoration('参数介绍'),
              onChanged: (value) =>
                  onChanged(field.copyWith(description: value)),
            ),
          ),
          kOpenHandGap8,
          SizedBox(
            height: _formControlHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: field.defaultValue,
                    decoration: _inputDecoration('默认值（可选）'),
                    onChanged: (value) =>
                        onChanged(field.copyWith(defaultValue: value)),
                  ),
                ),
                kOpenHandHGap8,
                SizedBox(
                  width: 82,
                  child: Semantics(
                    selected: field.required,
                    child: OutlinedButton(
                      onPressed: () =>
                          onChanged(field.copyWith(required: !field.required)),
                      style: OutlinedButton.styleFrom(
                        minimumSize: Size.zero,
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        backgroundColor: field.required
                            ? theme.colorScheme.primaryContainer
                            : theme.colorScheme.surfaceContainerLow,
                        foregroundColor: field.required
                            ? theme.colorScheme.onPrimaryContainer
                            : theme.colorScheme.onSurface,
                        side: BorderSide(
                          color: field.required
                              ? theme.colorScheme.primary.withValues(alpha: 0.5)
                              : theme.colorScheme.outlineVariant,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            kOpenHandRadius12,
                          ),
                        ),
                      ),
                      child: const Text('必需'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NumberFieldRow extends StatelessWidget {
  const _NumberFieldRow({
    required this.leftLabel,
    required this.leftValue,
    required this.leftMin,
    required this.leftMax,
    required this.onLeftChanged,
    required this.rightLabel,
    required this.rightValue,
    required this.rightMin,
    required this.rightMax,
    required this.onRightChanged,
  });

  final String leftLabel;
  final int leftValue;
  final int leftMin;
  final int leftMax;
  final ValueChanged<int> onLeftChanged;
  final String rightLabel;
  final int rightValue;
  final int rightMin;
  final int rightMax;
  final ValueChanged<int> onRightChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _LabeledField(
            label: leftLabel,
            child: TextFormField(
              key: ValueKey('$leftLabel-$leftValue'),
              initialValue: '$leftValue',
              keyboardType: TextInputType.number,
              decoration: _inputDecoration('$leftMin–$leftMax'),
              onChanged: (value) {
                final parsed = int.tryParse(value);
                if (parsed != null) {
                  onLeftChanged(parsed.clamp(leftMin, leftMax));
                }
              },
            ),
          ),
        ),
        kOpenHandHGap10,
        Expanded(
          child: _LabeledField(
            label: rightLabel,
            child: TextFormField(
              key: ValueKey('$rightLabel-$rightValue'),
              initialValue: '$rightValue',
              keyboardType: TextInputType.number,
              decoration: _inputDecoration('$rightMin–$rightMax'),
              onChanged: (value) {
                final parsed = int.tryParse(value);
                if (parsed != null) {
                  onRightChanged(parsed.clamp(rightMin, rightMax));
                }
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _ExecutionResultCard extends StatelessWidget {
  const _ExecutionResultCard({this.result, this.error});

  final String? result;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final failed = error != null;
    final color = failed
        ? theme.colorScheme.tertiary
        : theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(kOpenHandRadius14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                failed
                    ? Icons.error_outline_rounded
                    : Icons.check_circle_outline_rounded,
                color: color,
                size: 19,
              ),
              kOpenHandHGap8,
              Text(
                failed ? '测试失败' : '测试完成',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          kOpenHandGap8,
          SelectableText(
            error ?? result ?? '',
            style: theme.textTheme.bodySmall?.copyWith(height: 1.45),
          ),
        ],
      ),
    );
  }
}

InputDecoration _inputDecoration(String hint) {
  return InputDecoration(
    hintText: hint,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(kOpenHandRadius12),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(kOpenHandRadius12),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(kOpenHandRadius12),
    ),
  );
}

String _bodyFormatLabel(WorkflowHttpBodyFormat format) => switch (format) {
  WorkflowHttpBodyFormat.none => '无请求体',
  WorkflowHttpBodyFormat.json => 'JSON',
  WorkflowHttpBodyFormat.text => '原始文本',
  WorkflowHttpBodyFormat.formUrlEncoded => 'x-www-form-urlencoded',
  WorkflowHttpBodyFormat.formData => 'form-data',
};

({String label, String description, IconData icon, Color color})
workflowNodeDescriptor(WorkflowNodeKind kind, ColorScheme colors) {
  return switch (kind) {
    WorkflowNodeKind.condition => (
      label: '条件分支',
      description: '依据表达式选择后续路径',
      icon: Icons.call_split_rounded,
      color: colors.tertiary,
    ),
    WorkflowNodeKind.loop => (
      label: '循环',
      description: '按上限重复执行节点组',
      icon: Icons.loop_rounded,
      color: colors.secondary,
    ),
    WorkflowNodeKind.iteration => (
      label: '迭代',
      description: '逐项处理数组输入',
      icon: Icons.view_week_outlined,
      color: colors.primary,
    ),
    WorkflowNodeKind.llm => (
      label: 'LLM',
      description: '调用模型完成推理与生成',
      icon: Icons.auto_awesome_rounded,
      color: colors.primary,
    ),
    WorkflowNodeKind.httpRequest => (
      label: 'HTTP 请求',
      description: '调用外部 HTTP API',
      icon: Icons.language_rounded,
      color: colors.secondary,
    ),
  };
}

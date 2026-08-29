import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../app/model/app_settings_snapshot.dart'
    show RecentModelSelection;
import '../../../app/theme/openhand_status_colors.dart';
import '../../../shared/ui/animated_menu.dart';
import '../../../shared/ui/motion_durations.dart';
import '../../../shared/ui/motion_preference.dart';
import '../../../shared/ui/openhand_form_fields.dart';
import '../../../shared/ui/openhand_model_selector_field.dart';
import '../../../shared/ui/openhand_reveal_switcher.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../../ai/index.dart'
    show AiModelConfig, AiReasoningEffortOption, AiThreadTemplate;
import '../../instructions/index.dart' show UserInstructionEntry;
import '../../knowledge_base/index.dart' show KnowledgeSource;
import '../../mcp/index.dart' show McpServer;
import '../../memory/index.dart' show UserMemoryEntry;
import '../../skills/index.dart' show LocalSkill;
import '../model/workflow_definition.dart';
import 'workflow_parameter_reference_field.dart';

const double _formControlHeight = 52;
const double _configurationActionSize = 44;
const double _parameterTypeControlWidth = 146;
const double _valueSourceControlWidth = 112;
const Set<String> _httpMethodsWithoutBody = <String>{'GET', 'HEAD'};
const RoundedRectangleBorder _workflowButtonShape = RoundedRectangleBorder(
  borderRadius: kOpenHandBorderRadius12,
);
const Uuid _workflowConfigurationUuid = Uuid();

enum WorkflowNodeTestStatus { success, warning, failure }

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
    required this.availableReferences,
    required this.nestedOutputReferences,
    required this.reservedParameterNames,
    this.testResult,
    this.testError,
    this.testStatus,
  });

  final WorkflowNode node;
  final WorkflowEditorCatalog catalog;
  final ValueChanged<WorkflowNode> onChanged;
  final VoidCallback onClose;
  final VoidCallback onDelete;
  final VoidCallback onTest;
  final bool testing;
  final List<WorkflowParameterReference> availableReferences;
  final List<WorkflowParameterReference> nestedOutputReferences;
  final Map<String, String> reservedParameterNames;
  final String? testResult;
  final String? testError;
  final WorkflowNodeTestStatus? testStatus;

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
                if (node.kind != WorkflowNodeKind.start &&
                    node.kind != WorkflowNodeKind.end) ...[
                  _buildCommonTitle(context),
                  kOpenHandGap14,
                ],
                if (node.kind == WorkflowNodeKind.llm) ...[
                  _buildLlmInput(),
                  kOpenHandGap14,
                ],
                switch (node.kind) {
                  WorkflowNodeKind.start => _buildStart(),
                  WorkflowNodeKind.llm => _buildLlm(context),
                  WorkflowNodeKind.httpRequest => _buildHttp(context),
                  WorkflowNodeKind.condition => _buildCondition(context),
                  WorkflowNodeKind.loop => _buildLoop(context),
                  WorkflowNodeKind.iteration => _buildIteration(context),
                  WorkflowNodeKind.end => _buildEnd(),
                },
                OpenHandVerticalRevealSwitcher(
                  reverseDuration: kOpenHandVerticalRevealReverseDuration,
                  slideBeginOffsetY: -0.04,
                  child:
                      testStatus == null ||
                          (testResult == null && testError == null)
                      ? null
                      : Padding(
                          key: ValueKey<WorkflowNodeTestStatus>(testStatus!),
                          padding: const EdgeInsets.only(top: 16),
                          child: _ExecutionResultCard(
                            status: testStatus!,
                            message: testError ?? testResult ?? '',
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

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final descriptor = workflowNodeDescriptor(node.kind, theme.colorScheme);
    final actionStyle = IconButton.styleFrom(
      fixedSize: const Size.square(_configurationActionSize),
      padding: EdgeInsets.zero,
      shape: _workflowButtonShape,
      shadowColor: Colors.transparent,
    );
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
            style: actionStyle,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
          kOpenHandHGap6,
          IconButton(
            tooltip: '关闭配置',
            onPressed: onClose,
            style: actionStyle,
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

  Widget _buildStart() {
    return _FormSection(
      title: '输入内容',
      icon: Icons.input_rounded,
      child: _OutputFieldEditor(
        fields: node.inputFields(),
        addLabel: '添加输入参数',
        idPrefix: 'input',
        availableReferences: availableReferences,
        reservedParameterNames: reservedParameterNames,
        onChanged: (value) => _set(
          WorkflowSettingKeys.inputFields,
          value.map((item) => item.toJson()).toList(growable: false),
        ),
      ),
    );
  }

  Widget _buildEnd() {
    return _FormSection(
      title: '输出参数',
      icon: Icons.output_rounded,
      child: _OutputFieldEditor(
        fields: node.outputFields(),
        addLabel: '添加输出参数',
        idPrefix: 'output',
        availableReferences: availableReferences,
        reservedParameterNames: reservedParameterNames,
        onChanged: (value) => _set(
          WorkflowSettingKeys.outputFields,
          value.map((item) => item.toJson()).toList(growable: false),
        ),
      ),
    );
  }

  Widget _buildLlmInput() {
    return _FormSection(
      title: '输入内容',
      icon: Icons.input_rounded,
      child: WorkflowParameterReferenceField(
        key: ValueKey('input-${node.id}'),
        value: node.stringSetting(WorkflowSettingKeys.inputContent),
        references: availableReferences,
        minLines: 4,
        maxLines: 10,
        decoration: _inputDecoration('输入发送给模型的用户命令，输入 / 引用上游参数'),
        onChanged: (value) => _set(WorkflowSettingKeys.inputContent, value),
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
                helper: '输入 / 可快速引用上游节点的输出参数。',
                child: WorkflowParameterReferenceField(
                  key: ValueKey('prompt-${node.id}'),
                  value: node.stringSetting(WorkflowSettingKeys.prompt),
                  references: availableReferences,
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
    _setValues(<String, Object?>{
      WorkflowSettingKeys.modelConfigId: selection.$1,
      WorkflowSettingKeys.modelId: selection.$2,
      WorkflowSettingKeys.reasoningEffort:
          selectedModel?.resolvedReasoningEffort ?? '',
    });
  }

  Widget _buildHttp(BuildContext context) {
    final method = node
        .stringSetting(WorkflowSettingKeys.method, 'GET')
        .trim()
        .toUpperCase();
    final bodyVisible = !_httpMethodsWithoutBody.contains(method);
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
                        onChanged: (value) => _setHttpMethod(value ?? 'GET'),
                      ),
                    ),
                  ),
                  kOpenHandHGap10,
                  Expanded(
                    child: _LabeledField(
                      label: '请求 URL',
                      required: true,
                      child: WorkflowParameterReferenceField(
                        key: ValueKey('url-${node.id}'),
                        value: node.stringSetting(WorkflowSettingKeys.url),
                        references: availableReferences,
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
                availableReferences: availableReferences,
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
                availableReferences: availableReferences,
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
                                    onChanged: (value) => _setBodyFormat(
                                      value ?? WorkflowHttpBodyFormat.none,
                                    ),
                                  ),
                            ),
                            if (bodyFormat.usesFields) ...[
                              kOpenHandGap12,
                              _KeyValueEditor(
                                title: '请求体字段',
                                addLabel: '添加字段',
                                entries: node.keyValueSetting(
                                  WorkflowSettingKeys.bodyEntries,
                                ),
                                availableReferences: availableReferences,
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
                                child: WorkflowParameterReferenceField(
                                  key: ValueKey(
                                    'body-${node.id}-${bodyFormat.name}',
                                  ),
                                  value: node.stringSetting(
                                    WorkflowSettingKeys.body,
                                  ),
                                  references: availableReferences,
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
    final configuredCases = node.conditionCases();
    final cases = configuredCases.isEmpty
        ? _legacyConditionCases(node)
        : configuredCases;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FormSection(
          title: '分支条件',
          icon: Icons.call_split_rounded,
          child: _ConditionCasesEditor(
            cases: cases,
            availableReferences: availableReferences,
            onChanged: (value) => _set(
              WorkflowSettingKeys.conditionCases,
              value.map((item) => item.toJson()).toList(growable: false),
            ),
          ),
        ),
        kOpenHandGap16,
        _buildTestButton(),
      ],
    );
  }

  Widget _buildLoop(BuildContext context) {
    final variables = node.loopVariables();
    final breakConditions = node.loopBreakConditions();
    final conditionLogic = WorkflowConditionLogic.fromStorage(
      node.settings[WorkflowSettingKeys.loopConditionLogic],
    );
    final loopReferences = <WorkflowParameterReference>[
      ...availableReferences,
      ...nestedOutputReferences,
      ...variables
          .where(
            (variable) =>
                workflowParameterNamePattern.hasMatch(variable.name.trim()),
          )
          .map(
            (variable) => WorkflowParameterReference(
              nodeId: node.id,
              nodeTitle: '当前循环',
              field: WorkflowOutputField(
                id: variable.id,
                name: variable.name.trim(),
                description: '循环变量',
                type: variable.type,
              ),
            ),
          ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FormSection(
          title: '循环变量',
          icon: Icons.data_array_rounded,
          child: _LoopVariableEditor(
            variables: variables,
            availableReferences: availableReferences,
            reservedParameterNames: reservedParameterNames,
            onChanged: (value) => _set(
              WorkflowSettingKeys.loopVariables,
              value.map((item) => item.toJson()).toList(growable: false),
            ),
          ),
        ),
        kOpenHandGap14,
        _FormSection(
          title: '退出条件',
          icon: Icons.output_rounded,
          child: _ConditionGroupEditor(
            conditions: breakConditions,
            logic: conditionLogic,
            availableReferences: loopReferences,
            emptyHint: '未配置退出条件时，将在达到最大循环次数后结束。',
            onConditionsChanged: (value) => _set(
              WorkflowSettingKeys.loopBreakConditions,
              value.map((item) => item.toJson()).toList(growable: false),
            ),
            onLogicChanged: (value) => _set(
              WorkflowSettingKeys.loopConditionLogic,
              value.storageValue,
            ),
          ),
        ),
        kOpenHandGap14,
        _FormSection(
          title: '循环上限',
          icon: Icons.repeat_on_rounded,
          child: _LabeledField(
            label: '最大循环次数',
            helper: '限制为 1–1000 次，达到退出条件时会提前结束。',
            child: TextFormField(
              key: ValueKey('loop-count-${node.id}'),
              initialValue:
                  '${node.intSetting(WorkflowSettingKeys.maxIterations, 10)}',
              keyboardType: TextInputType.number,
              decoration: _inputDecoration('1–1000'),
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
    final parallel = node.boolSetting(WorkflowSettingKeys.iterationParallel);
    final errorMode = WorkflowIterationErrorMode.fromStorage(
      node.settings[WorkflowSettingKeys.iterationErrorMode],
    );
    final outputName = node.stringSetting(
      WorkflowSettingKeys.iterationOutputName,
      'iteration_result',
    );
    final normalizedOutputName = outputName.trim();
    final outputNameOwner = reservedParameterNames[normalizedOutputName];
    final outputNameError = normalizedOutputName.isEmpty
        ? '请输入输出参数名称。'
        : !workflowParameterNamePattern.hasMatch(normalizedOutputName)
        ? '名称须以英文字母或下划线开头，仅包含字母、数字和下划线。'
        : outputNameOwner == null
        ? null
        : '参数已由节点“$outputNameOwner”使用。';
    final iterationReferences = <WorkflowParameterReference>[
      ...availableReferences,
      ...nestedOutputReferences,
      WorkflowParameterReference(
        nodeId: node.id,
        nodeTitle: '当前迭代',
        field: const WorkflowOutputField(
          id: 'iteration-item',
          name: 'item',
          description: '当前数组项',
          type: WorkflowOutputType.object,
        ),
      ),
      WorkflowParameterReference(
        nodeId: node.id,
        nodeTitle: '当前迭代',
        field: const WorkflowOutputField(
          id: 'iteration-index',
          name: 'index',
          description: '当前索引',
          type: WorkflowOutputType.integer,
        ),
      ),
      WorkflowParameterReference(
        nodeId: node.id,
        nodeTitle: '当前迭代',
        field: const WorkflowOutputField(
          id: 'iteration-length',
          name: 'length',
          description: '数组长度',
          type: WorkflowOutputType.integer,
        ),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FormSection(
          title: '迭代输入与输出',
          icon: Icons.view_week_outlined,
          child: Column(
            children: [
              _LabeledField(
                label: '数组输入',
                required: true,
                helper: '输入 / 引用数组参数，最多处理前 1000 项。',
                child: WorkflowParameterReferenceField(
                  key: ValueKey('iteration-input-${node.id}'),
                  value: node.stringSetting(WorkflowSettingKeys.iterationInput),
                  references: availableReferences,
                  decoration: _inputDecoration('引用上游数组参数'),
                  onChanged: (value) =>
                      _set(WorkflowSettingKeys.iterationInput, value),
                ),
              ),
              kOpenHandGap12,
              _LabeledField(
                label: '输出参数名称',
                required: true,
                helper: '用于后续节点引用迭代结果数组，工作流内不可重名。',
                child: TextFormField(
                  key: ValueKey('iteration-output-name-${node.id}'),
                  initialValue: outputName,
                  decoration: _inputDecoration(
                    'iteration_result',
                  ).copyWith(errorText: outputNameError),
                  onChanged: (value) =>
                      _set(WorkflowSettingKeys.iterationOutputName, value),
                ),
              ),
              kOpenHandGap12,
              _LabeledField(
                label: '输出映射',
                required: true,
                helper: '可使用 {{item}}、{{index}}、{{length}} 生成每项输出。',
                child: WorkflowParameterReferenceField(
                  key: ValueKey('iteration-output-${node.id}'),
                  value: node.stringSetting(
                    WorkflowSettingKeys.iterationOutput,
                    '{{item}}',
                  ),
                  references: iterationReferences,
                  decoration: _inputDecoration('{{item}}'),
                  onChanged: (value) =>
                      _set(WorkflowSettingKeys.iterationOutput, value),
                ),
              ),
            ],
          ),
        ),
        kOpenHandGap14,
        _FormSection(
          title: '执行策略',
          icon: Icons.tune_rounded,
          child: Column(
            children: [
              _SwitchSetting(
                title: '并行模式',
                description: '并发处理数组项，适用于相互独立的迭代任务。',
                value: parallel,
                onChanged: (value) =>
                    _set(WorkflowSettingKeys.iterationParallel, value),
              ),
              OpenHandVerticalRevealSwitcher(
                child: parallel
                    ? Padding(
                        key: const ValueKey('iteration-parallelism'),
                        padding: const EdgeInsets.only(top: 12),
                        child: _LabeledField(
                          label: '最大并行度',
                          helper: '限制为 1–10，避免瞬时占用过多资源。',
                          child: TextFormField(
                            key: ValueKey('parallelism-${node.id}'),
                            initialValue:
                                '${node.intSetting(WorkflowSettingKeys.iterationParallelism, 10)}',
                            keyboardType: TextInputType.number,
                            decoration: _inputDecoration('1–10'),
                            onChanged: (value) {
                              final parsed = int.tryParse(value);
                              if (parsed != null) {
                                _set(
                                  WorkflowSettingKeys.iterationParallelism,
                                  parsed.clamp(1, 10),
                                );
                              }
                            },
                          ),
                        ),
                      )
                    : null,
              ),
              kOpenHandGap12,
              _LabeledField(
                label: '异常处理',
                child:
                    AnimatedDropdownButtonFormField<WorkflowIterationErrorMode>(
                      initialValue: errorMode,
                      decoration: _inputDecoration('选择异常处理方式'),
                      items: WorkflowIterationErrorMode.values
                          .map(
                            (mode) =>
                                DropdownMenuItem<WorkflowIterationErrorMode>(
                                  value: mode,
                                  child: Text(_iterationErrorModeLabel(mode)),
                                ),
                          )
                          .toList(growable: false),
                      onChanged: (value) => _set(
                        WorkflowSettingKeys.iterationErrorMode,
                        (value ?? WorkflowIterationErrorMode.stop).storageValue,
                      ),
                    ),
              ),
              kOpenHandGap12,
              _SwitchSetting(
                title: '扁平化输出',
                description: '当每项输出均为数组时，合并为单层数组。',
                value: node.boolSetting(
                  WorkflowSettingKeys.iterationFlattenOutput,
                  true,
                ),
                onChanged: (value) =>
                    _set(WorkflowSettingKeys.iterationFlattenOutput, value),
              ),
            ],
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
        onChanged: (value) => _setValues(<String, Object?>{
          WorkflowSettingKeys.structuredOutput: value,
          if (!value) WorkflowSettingKeys.outputFields: <Object?>[],
        }),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            enabled
                ? '按参数定义生成并校验结构化结果；解析失败会使节点执行失败。'
                : '关闭时返回原始响应，并清空已配置的输出参数。',
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
                      addLabel: '添加输出参数',
                      idPrefix: 'output',
                      availableReferences: availableReferences,
                      reservedParameterNames: reservedParameterNames,
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
      style: FilledButton.styleFrom(shape: _workflowButtonShape),
      icon: testing
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.play_arrow_rounded),
      label: Text(testing ? '正在测试' : '测试当前节点'),
    );
  }

  void _setHttpMethod(String method) {
    final clearBody = _httpMethodsWithoutBody.contains(method);
    _setValues(<String, Object?>{
      WorkflowSettingKeys.method: method,
      if (clearBody)
        WorkflowSettingKeys.bodyFormat:
            WorkflowHttpBodyFormat.none.storageValue,
      if (clearBody) WorkflowSettingKeys.body: '',
      if (clearBody) WorkflowSettingKeys.bodyEntries: <Object?>[],
    });
  }

  void _setBodyFormat(WorkflowHttpBodyFormat format) {
    _setValues(<String, Object?>{
      WorkflowSettingKeys.bodyFormat: format.storageValue,
      if (format == WorkflowHttpBodyFormat.none || format.usesFields)
        WorkflowSettingKeys.body: '',
      if (!format.usesFields) WorkflowSettingKeys.bodyEntries: <Object?>[],
    });
  }

  void _set(String key, Object? value) =>
      _setValues(<String, Object?>{key: value});

  void _setValues(Map<String, Object?> values) {
    onChanged(
      node.copyWith(settings: <String, Object?>{...node.settings, ...values}),
    );
  }

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
                            shape: _workflowButtonShape,
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

class _ConditionCasesEditor extends StatelessWidget {
  const _ConditionCasesEditor({
    required this.cases,
    required this.availableReferences,
    required this.onChanged,
  });

  final List<WorkflowConditionCase> cases;
  final List<WorkflowParameterReference> availableReferences;
  final ValueChanged<List<WorkflowConditionCase>> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...cases.indexed.map((entry) {
          final (index, item) = entry;
          return Padding(
            key: ValueKey(item.id),
            padding: EdgeInsets.only(
              bottom: index == cases.length - 1 ? 0 : 10,
            ),
            child: _EntryCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.tertiaryContainer,
                          borderRadius: BorderRadius.circular(kOpenHandRadius8),
                        ),
                        child: Text(
                          index == 0 ? 'IF' : 'ELIF $index',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onTertiaryContainer,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (cases.length > 1) ...[
                        IconButton(
                          tooltip: '上移分支',
                          onPressed: index == 0
                              ? null
                              : () => _move(index, index - 1),
                          style: IconButton.styleFrom(
                            fixedSize: const Size.square(34),
                            padding: EdgeInsets.zero,
                            shape: _workflowButtonShape,
                          ),
                          icon: const Icon(
                            Icons.arrow_upward_rounded,
                            size: 17,
                          ),
                        ),
                        kOpenHandHGap6,
                        IconButton(
                          tooltip: '下移分支',
                          onPressed: index == cases.length - 1
                              ? null
                              : () => _move(index, index + 1),
                          style: IconButton.styleFrom(
                            fixedSize: const Size.square(34),
                            padding: EdgeInsets.zero,
                            shape: _workflowButtonShape,
                          ),
                          icon: const Icon(
                            Icons.arrow_downward_rounded,
                            size: 17,
                          ),
                        ),
                      ],
                      if (index > 0) ...[
                        kOpenHandHGap6,
                        IconButton(
                          tooltip: '删除分支',
                          onPressed: () => onChanged(
                            cases
                                .where((candidate) => candidate.id != item.id)
                                .toList(growable: false),
                          ),
                          style: IconButton.styleFrom(
                            fixedSize: const Size.square(36),
                            padding: EdgeInsets.zero,
                            shape: _workflowButtonShape,
                          ),
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 19,
                          ),
                        ),
                      ],
                    ],
                  ),
                  kOpenHandGap10,
                  _ConditionGroupEditor(
                    conditions: item.conditions,
                    logic: item.logic,
                    availableReferences: availableReferences,
                    onConditionsChanged: (value) =>
                        _replace(item.copyWith(conditions: value)),
                    onLogicChanged: (value) =>
                        _replace(item.copyWith(logic: value)),
                  ),
                ],
              ),
            ),
          );
        }),
        kOpenHandGap10,
        OutlinedButton.icon(
          onPressed: () => onChanged(<WorkflowConditionCase>[
            ...cases,
            WorkflowConditionCase(
              id: _workflowConfigurationUuid.v4(),
              conditions: <WorkflowConditionClause>[
                WorkflowConditionClause(id: _workflowConfigurationUuid.v4()),
              ],
            ),
          ]),
          icon: const Icon(Icons.add_rounded),
          label: const Text('添加 ELIF 分支'),
          style: OutlinedButton.styleFrom(shape: _workflowButtonShape),
        ),
        kOpenHandGap10,
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(kOpenHandRadius12),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              Icon(
                Icons.alt_route_rounded,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              kOpenHandHGap8,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ELSE',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '当前面的分支均不匹配时进入此分支。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _replace(WorkflowConditionCase updated) {
    onChanged(
      cases
          .map((item) => item.id == updated.id ? updated : item)
          .toList(growable: false),
    );
  }

  void _move(int from, int to) {
    final reordered = List<WorkflowConditionCase>.from(cases);
    final item = reordered.removeAt(from);
    reordered.insert(to, item);
    onChanged(reordered);
  }
}

class _ConditionGroupEditor extends StatelessWidget {
  const _ConditionGroupEditor({
    required this.conditions,
    required this.logic,
    required this.availableReferences,
    required this.onConditionsChanged,
    required this.onLogicChanged,
    this.emptyHint = '至少添加一个条件。',
  });

  final List<WorkflowConditionClause> conditions;
  final WorkflowConditionLogic logic;
  final List<WorkflowParameterReference> availableReferences;
  final ValueChanged<List<WorkflowConditionClause>> onConditionsChanged;
  final ValueChanged<WorkflowConditionLogic> onLogicChanged;
  final String emptyHint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (conditions.length > 1) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  '条件关系',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SizedBox(
                width: 128,
                child: AnimatedDropdownButtonFormField<WorkflowConditionLogic>(
                  initialValue: logic,
                  decoration: _inputDecoration('条件关系'),
                  items: WorkflowConditionLogic.values
                      .map(
                        (item) => DropdownMenuItem<WorkflowConditionLogic>(
                          value: item,
                          child: Text(_conditionLogicLabel(item)),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) =>
                      onLogicChanged(value ?? WorkflowConditionLogic.all),
                ),
              ),
            ],
          ),
          kOpenHandGap10,
        ],
        if (conditions.isEmpty)
          Text(
            emptyHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          ...conditions.indexed.map((entry) {
            final (index, condition) = entry;
            return Padding(
              key: ValueKey(condition.id),
              padding: EdgeInsets.only(
                bottom: index == conditions.length - 1 ? 0 : 8,
              ),
              child: Column(
                children: [
                  _ConditionClauseCard(
                    condition: condition,
                    availableReferences: availableReferences,
                    onChanged: (updated) => onConditionsChanged(
                      conditions
                          .map((item) => item.id == updated.id ? updated : item)
                          .toList(growable: false),
                    ),
                    onDelete: () => onConditionsChanged(
                      conditions
                          .where((item) => item.id != condition.id)
                          .toList(growable: false),
                    ),
                  ),
                  if (index < conditions.length - 1)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        _conditionLogicLabel(logic),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                ],
              ),
            );
          }),
        kOpenHandGap10,
        OutlinedButton.icon(
          onPressed: () => onConditionsChanged(<WorkflowConditionClause>[
            ...conditions,
            WorkflowConditionClause(id: _workflowConfigurationUuid.v4()),
          ]),
          icon: const Icon(Icons.add_rounded),
          label: const Text('添加条件'),
          style: OutlinedButton.styleFrom(shape: _workflowButtonShape),
        ),
      ],
    );
  }
}

class _ConditionClauseCard extends StatelessWidget {
  const _ConditionClauseCard({
    required this.condition,
    required this.availableReferences,
    required this.onChanged,
    required this.onDelete,
  });

  final WorkflowConditionClause condition;
  final List<WorkflowParameterReference> availableReferences;
  final ValueChanged<WorkflowConditionClause> onChanged;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(kOpenHandRadius12),
      ),
      child: Column(
        children: [
          WorkflowParameterReferenceField(
            key: ValueKey('${condition.id}-variable'),
            value: condition.variable,
            references: availableReferences,
            decoration: _inputDecoration('变量或参数引用'),
            onChanged: (value) =>
                onChanged(condition.copyWith(variable: value)),
          ),
          kOpenHandGap8,
          SizedBox(
            height: _formControlHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child:
                      AnimatedDropdownButtonFormField<
                        WorkflowConditionOperator
                      >(
                        initialValue: condition.operator,
                        decoration: _inputDecoration('比较方式'),
                        items: WorkflowConditionOperator.values
                            .map(
                              (operator) =>
                                  DropdownMenuItem<WorkflowConditionOperator>(
                                    value: operator,
                                    child: Text(
                                      _conditionOperatorLabel(operator),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                            )
                            .toList(growable: false),
                        onChanged: (value) => onChanged(
                          condition.copyWith(
                            operator: value ?? WorkflowConditionOperator.equals,
                          ),
                        ),
                      ),
                ),
                kOpenHandHGap8,
                IconButton.filledTonal(
                  tooltip: '删除条件',
                  onPressed: onDelete,
                  style: IconButton.styleFrom(
                    fixedSize: const Size.square(_formControlHeight),
                    padding: EdgeInsets.zero,
                    shape: _workflowButtonShape,
                    shadowColor: Colors.transparent,
                  ),
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                ),
              ],
            ),
          ),
          OpenHandVerticalRevealSwitcher(
            child: condition.operator.requiresValue
                ? Padding(
                    key: ValueKey('${condition.id}-value'),
                    padding: const EdgeInsets.only(top: 8),
                    child: SizedBox(
                      height: _formControlHeight,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: _valueSourceControlWidth,
                            child: _ValueSourceDropdown(
                              value: condition.valueSource,
                              onChanged: (value) => onChanged(
                                condition.copyWith(valueSource: value),
                              ),
                            ),
                          ),
                          kOpenHandHGap8,
                          Expanded(
                            child: _WorkflowTypedValueField(
                              value: condition.value,
                              type: WorkflowOutputType.string,
                              source: condition.valueSource,
                              references: availableReferences,
                              label: '比较值',
                              filterReferencesByType: false,
                              onChanged: (value) =>
                                  onChanged(condition.copyWith(value: value)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

class _LoopVariableEditor extends StatelessWidget {
  const _LoopVariableEditor({
    required this.variables,
    required this.availableReferences,
    required this.reservedParameterNames,
    required this.onChanged,
  });

  final List<WorkflowLoopVariable> variables;
  final List<WorkflowParameterReference> availableReferences;
  final Map<String, String> reservedParameterNames;
  final ValueChanged<List<WorkflowLoopVariable>> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (variables.isEmpty)
          Text(
            '添加循环内可读写的局部变量。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          ...variables.map(
            (variable) => Padding(
              key: ValueKey(variable.id),
              padding: const EdgeInsets.only(bottom: 10),
              child: _EntryCard(
                child: Column(
                  children: [
                    SizedBox(
                      height: _formControlHeight,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: TextFormField(
                              initialValue: variable.name,
                              decoration: _loopVariableNameDecoration(
                                context,
                                variable,
                              ),
                              onChanged: (value) =>
                                  _replace(variable.copyWith(name: value)),
                            ),
                          ),
                          kOpenHandHGap8,
                          SizedBox(
                            width: _parameterTypeControlWidth,
                            child:
                                AnimatedDropdownButtonFormField<
                                  WorkflowOutputType
                                >(
                                  initialValue: variable.type,
                                  decoration: _inputDecoration('类型'),
                                  items: WorkflowOutputType.values
                                      .map(
                                        (type) =>
                                            DropdownMenuItem<
                                              WorkflowOutputType
                                            >(
                                              value: type,
                                              child: Text(type.label),
                                            ),
                                      )
                                      .toList(growable: false),
                                  onChanged: (value) => _replace(
                                    variable.copyWith(
                                      type: value ?? WorkflowOutputType.string,
                                    ),
                                  ),
                                ),
                          ),
                          kOpenHandHGap8,
                          IconButton.filledTonal(
                            tooltip: '删除循环变量',
                            onPressed: () => onChanged(
                              variables
                                  .where((item) => item.id != variable.id)
                                  .toList(growable: false),
                            ),
                            style: IconButton.styleFrom(
                              fixedSize: const Size.square(_formControlHeight),
                              padding: EdgeInsets.zero,
                              shape: _workflowButtonShape,
                              shadowColor: Colors.transparent,
                            ),
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              size: 20,
                            ),
                          ),
                        ],
                      ),
                    ),
                    kOpenHandGap8,
                    SizedBox(
                      height: _formControlHeight,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: _valueSourceControlWidth,
                            child: _ValueSourceDropdown(
                              value: variable.valueSource,
                              onChanged: (value) => _replace(
                                variable.copyWith(valueSource: value),
                              ),
                            ),
                          ),
                          kOpenHandHGap8,
                          Expanded(
                            child: _WorkflowTypedValueField(
                              value: variable.initialValue,
                              type: variable.type,
                              source: variable.valueSource,
                              references: availableReferences,
                              label: '初始值（必填）',
                              onChanged: (value) => _replace(
                                variable.copyWith(initialValue: value),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        OutlinedButton.icon(
          onPressed: () => onChanged(<WorkflowLoopVariable>[
            ...variables,
            WorkflowLoopVariable(id: _workflowConfigurationUuid.v4()),
          ]),
          icon: const Icon(Icons.add_rounded),
          label: const Text('添加循环变量'),
          style: OutlinedButton.styleFrom(shape: _workflowButtonShape),
        ),
      ],
    );
  }

  InputDecoration _loopVariableNameDecoration(
    BuildContext context,
    WorkflowLoopVariable variable,
  ) {
    final name = variable.name.trim();
    final duplicate =
        variables.where((item) => item.name.trim() == name).length > 1;
    final invalid =
        name.isNotEmpty &&
        (!workflowParameterNamePattern.hasMatch(name) ||
            duplicate ||
            reservedParameterNames.containsKey(name));
    if (!invalid) return _inputDecoration('变量名称');
    final color = Theme.of(context).colorScheme.error;
    return _inputDecoration('变量名称').copyWith(
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kOpenHandRadius12),
        borderSide: BorderSide(color: color),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kOpenHandRadius12),
        borderSide: BorderSide(color: color, width: 2),
      ),
    );
  }

  void _replace(WorkflowLoopVariable updated) {
    onChanged(
      variables
          .map((item) => item.id == updated.id ? updated : item)
          .toList(growable: false),
    );
  }
}

class _SwitchSetting extends StatelessWidget {
  const _SwitchSetting({
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        kOpenHandHGap10,
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}

class _KeyValueEditor extends StatelessWidget {
  const _KeyValueEditor({
    required this.title,
    required this.addLabel,
    required this.entries,
    required this.availableReferences,
    required this.onChanged,
  });

  final String title;
  final String addLabel;
  final List<WorkflowKeyValueEntry> entries;
  final List<WorkflowParameterReference> availableReferences;
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
              style: TextButton.styleFrom(shape: _workflowButtonShape),
            ),
          ],
        ),
        AnimatedSize(
          duration: openHandMotionDuration(context, kOpenHandMotion220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: entries.isEmpty
              ? const SizedBox.shrink()
              : Column(
                  children: entries
                      .map((entry) {
                        final index = entries.indexOf(entry);
                        return Padding(
                          key: ValueKey(entry.id),
                          padding: EdgeInsets.only(top: index == 0 ? 12 : 8),
                          child: _EntryCard(
                            child: Column(
                              children: [
                                SizedBox(
                                  height: _formControlHeight,
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Expanded(
                                        child: WorkflowParameterReferenceField(
                                          key: ValueKey('${entry.id}-key'),
                                          value: entry.key,
                                          references: availableReferences,
                                          decoration: _inputDecoration('键（必填）'),
                                          onChanged: (value) => _replaceEntry(
                                            entry.copyWith(key: value),
                                          ),
                                        ),
                                      ),
                                      kOpenHandHGap8,
                                      IconButton.filledTonal(
                                        tooltip: '移除',
                                        onPressed: () => onChanged(
                                          entries
                                              .where(
                                                (item) => item.id != entry.id,
                                              )
                                              .toList(growable: false),
                                        ),
                                        style: IconButton.styleFrom(
                                          fixedSize: const Size.square(
                                            _formControlHeight,
                                          ),
                                          padding: EdgeInsets.zero,
                                          shape: _workflowButtonShape,
                                          shadowColor: Colors.transparent,
                                        ),
                                        icon: const Icon(
                                          Icons.close_rounded,
                                          size: 18,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                kOpenHandGap8,
                                SizedBox(
                                  height: _formControlHeight,
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      SizedBox(
                                        width: _valueSourceControlWidth,
                                        child: _ValueSourceDropdown(
                                          value: entry.valueSource,
                                          onChanged: (value) => _replaceEntry(
                                            entry.copyWith(valueSource: value),
                                          ),
                                        ),
                                      ),
                                      kOpenHandHGap8,
                                      Expanded(
                                        child: _WorkflowTypedValueField(
                                          value: entry.value,
                                          type: WorkflowOutputType.string,
                                          source: entry.valueSource,
                                          references: availableReferences,
                                          label: '值（必填）',
                                          filterReferencesByType: false,
                                          onChanged: (value) => _replaceEntry(
                                            entry.copyWith(value: value),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      })
                      .toList(growable: false),
                ),
        ),
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
  const _OutputFieldEditor({
    required this.fields,
    required this.addLabel,
    required this.idPrefix,
    required this.availableReferences,
    required this.reservedParameterNames,
    required this.onChanged,
  });

  final List<WorkflowOutputField> fields;
  final String addLabel;
  final String idPrefix;
  final List<WorkflowParameterReference> availableReferences;
  final Map<String, String> reservedParameterNames;
  final ValueChanged<List<WorkflowOutputField>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedSize(
          duration: openHandMotionDuration(context, kOpenHandMotion220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: fields.isEmpty
              ? const SizedBox.shrink()
              : Column(
                  children: fields
                      .map(
                        (field) => _OutputFieldCard(
                          key: ValueKey(field.id),
                          field: field,
                          availableReferences: availableReferences,
                          nameError: _nameError(field),
                          onChanged: (updated) => onChanged(
                            fields
                                .map(
                                  (item) =>
                                      item.id == updated.id ? updated : item,
                                )
                                .toList(growable: false),
                          ),
                          onDelete: () => onChanged(
                            fields
                                .where((item) => item.id != field.id)
                                .toList(growable: false),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
        ),
        kOpenHandGap10,
        OutlinedButton.icon(
          onPressed: () => onChanged(<WorkflowOutputField>[
            ...fields,
            WorkflowOutputField(
              id: '$idPrefix-${DateTime.now().microsecondsSinceEpoch}',
            ),
          ]),
          icon: const Icon(Icons.add_rounded),
          label: Text(addLabel),
          style: OutlinedButton.styleFrom(shape: _workflowButtonShape),
        ),
      ],
    );
  }

  String? _nameError(WorkflowOutputField field) {
    final name = field.name.trim();
    if (name.isEmpty) return null;
    if (!workflowParameterNamePattern.hasMatch(name)) {
      return '参数名称须以英文字母或下划线开头，仅包含字母、数字和下划线。';
    }
    if (fields.where((item) => item.name.trim() == name).length > 1) {
      return '当前节点中已存在参数“$name”。';
    }
    final owner = reservedParameterNames[name];
    return owner == null ? null : '参数“$name”已由节点“$owner”使用。';
  }
}

class _OutputFieldCard extends StatelessWidget {
  const _OutputFieldCard({
    super.key,
    required this.field,
    required this.availableReferences,
    required this.nameError,
    required this.onChanged,
    required this.onDelete,
  });

  final WorkflowOutputField field;
  final List<WorkflowParameterReference> availableReferences;
  final String? nameError;
  final ValueChanged<WorkflowOutputField> onChanged;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nameDecoration = nameError == null
        ? _inputDecoration('参数名称')
        : _inputDecoration('参数名称').copyWith(
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(kOpenHandRadius12),
              borderSide: BorderSide(color: theme.colorScheme.error),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(kOpenHandRadius12),
              borderSide: BorderSide(color: theme.colorScheme.error, width: 2),
            ),
          );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _EntryCard(
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
                      decoration: nameDecoration,
                      onChanged: (value) =>
                          onChanged(field.copyWith(name: value)),
                    ),
                  ),
                  kOpenHandHGap8,
                  SizedBox(
                    width: _parameterTypeControlWidth,
                    child: AnimatedDropdownButtonFormField<WorkflowOutputType>(
                      isExpanded: true,
                      initialValue: field.type,
                      decoration: _inputDecoration('类型'),
                      items: WorkflowOutputType.values
                          .map(
                            (type) => DropdownMenuItem<WorkflowOutputType>(
                              value: type,
                              child: Text(type.label),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) => onChanged(
                        field.copyWith(
                          type: value ?? WorkflowOutputType.string,
                        ),
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
                      shape: _workflowButtonShape,
                      shadowColor: Colors.transparent,
                    ),
                    icon: const Icon(Icons.delete_outline_rounded, size: 20),
                  ),
                ],
              ),
            ),
            AnimatedSize(
              duration: openHandMotionDuration(context, kOpenHandMotion180),
              curve: Curves.easeOutCubic,
              child: nameError == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          nameError!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
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
                  SizedBox(
                    width: _valueSourceControlWidth,
                    child: _ValueSourceDropdown(
                      value: field.valueSource,
                      onChanged: (value) =>
                          onChanged(field.copyWith(valueSource: value)),
                    ),
                  ),
                  kOpenHandHGap8,
                  Expanded(
                    child: _WorkflowTypedValueField(
                      value: field.defaultValue,
                      type: field.type,
                      source: field.valueSource,
                      references: availableReferences,
                      label: '默认值（可选）',
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
                        onPressed: () => onChanged(
                          field.copyWith(required: !field.required),
                        ),
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
                                ? theme.colorScheme.primary.withValues(
                                    alpha: 0.5,
                                  )
                                : theme.colorScheme.outlineVariant,
                          ),
                          shape: _workflowButtonShape,
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
      ),
    );
  }
}

class _ValueSourceDropdown extends StatelessWidget {
  const _ValueSourceDropdown({required this.value, required this.onChanged});

  final WorkflowValueSource value;
  final ValueChanged<WorkflowValueSource> onChanged;

  @override
  Widget build(BuildContext context) {
    return AnimatedDropdownButtonFormField<WorkflowValueSource>(
      isExpanded: true,
      initialValue: value,
      decoration: _inputDecoration('取值方式'),
      items: WorkflowValueSource.values
          .map(
            (source) => DropdownMenuItem<WorkflowValueSource>(
              value: source,
              child: Text(source.label, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(growable: false),
      onChanged: (source) => onChanged(source ?? WorkflowValueSource.constant),
    );
  }
}

class _WorkflowTypedValueField extends StatelessWidget {
  const _WorkflowTypedValueField({
    required this.value,
    required this.type,
    required this.source,
    required this.references,
    required this.label,
    required this.onChanged,
    this.filterReferencesByType = true,
  });

  final String value;
  final WorkflowOutputType type;
  final WorkflowValueSource source;
  final List<WorkflowParameterReference> references;
  final String label;
  final ValueChanged<String> onChanged;
  final bool filterReferencesByType;

  @override
  Widget build(BuildContext context) {
    if (source == WorkflowValueSource.variable) {
      final compatibleReferences = filterReferencesByType
          ? references
                .where(
                  (reference) =>
                      type.acceptsReferenceType(reference.field.type),
                )
                .toList(growable: false)
          : references;
      return WorkflowParameterReferenceField(
        key: ValueKey('$label-${type.storageValue}-${source.storageValue}'),
        value: value,
        references: compatibleReferences,
        decoration: _inputDecoration(label),
        onChanged: onChanged,
      );
    }

    if (type == WorkflowOutputType.boolean) {
      final normalized = value.trim().toLowerCase();
      return AnimatedDropdownButtonFormField<String>(
        key: ValueKey('$label-${type.storageValue}-${source.storageValue}'),
        isExpanded: true,
        initialValue: normalized == 'true' || normalized == 'false'
            ? normalized
            : null,
        decoration: _inputDecoration(label),
        items: const <DropdownMenuItem<String>>[
          DropdownMenuItem(value: 'true', child: Text('true')),
          DropdownMenuItem(value: 'false', child: Text('false')),
        ],
        onChanged: (next) {
          if (next != null) onChanged(next);
        },
      );
    }

    return TextFormField(
      key: ValueKey('$label-${type.storageValue}-${source.storageValue}'),
      initialValue: value,
      keyboardType:
          type == WorkflowOutputType.integer ||
              type == WorkflowOutputType.number
          ? const TextInputType.numberWithOptions(decimal: true, signed: true)
          : TextInputType.text,
      decoration: _inputDecoration(label),
      onChanged: onChanged,
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(kOpenHandRadius14),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: child,
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
  const _ExecutionResultCard({required this.status, required this.message});

  final WorkflowNodeTestStatus status;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (color, icon, title) = switch (status) {
      WorkflowNodeTestStatus.success => (
        OpenHandStatusColors.success,
        Icons.check_circle_outline_rounded,
        '测试成功',
      ),
      WorkflowNodeTestStatus.warning => (
        OpenHandStatusColors.warning,
        Icons.warning_amber_rounded,
        '测试异常',
      ),
      WorkflowNodeTestStatus.failure => (
        OpenHandStatusColors.error,
        Icons.error_outline_rounded,
        '测试失败',
      ),
    };
    final dark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: dark ? 0.16 : 0.1),
        borderRadius: BorderRadius.circular(kOpenHandRadius14),
        border: Border.all(color: color.withValues(alpha: dark ? 0.55 : 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: dark ? 0.2 : 0.14),
                  borderRadius: BorderRadius.circular(kOpenHandRadius10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              kOpenHandHGap10,
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          kOpenHandGap8,
          SelectableText(
            message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface,
              height: 1.45,
            ),
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

String _conditionLogicLabel(WorkflowConditionLogic logic) => switch (logic) {
  WorkflowConditionLogic.all => 'AND',
  WorkflowConditionLogic.any => 'OR',
};

String _conditionOperatorLabel(WorkflowConditionOperator operator) =>
    switch (operator) {
      WorkflowConditionOperator.equals => '等于',
      WorkflowConditionOperator.notEquals => '不等于',
      WorkflowConditionOperator.contains => '包含',
      WorkflowConditionOperator.notContains => '不包含',
      WorkflowConditionOperator.startsWith => '开头是',
      WorkflowConditionOperator.endsWith => '结尾是',
      WorkflowConditionOperator.greaterThan => '大于',
      WorkflowConditionOperator.lessThan => '小于',
      WorkflowConditionOperator.greaterThanOrEqual => '大于等于',
      WorkflowConditionOperator.lessThanOrEqual => '小于等于',
      WorkflowConditionOperator.isEmpty => '为空',
      WorkflowConditionOperator.isNotEmpty => '不为空',
      WorkflowConditionOperator.isNull => '为 null',
      WorkflowConditionOperator.isNotNull => '不为 null',
    };

String _iterationErrorModeLabel(WorkflowIterationErrorMode mode) =>
    switch (mode) {
      WorkflowIterationErrorMode.stop => '异常时终止',
      WorkflowIterationErrorMode.continueOnError => '记录异常并继续',
      WorkflowIterationErrorMode.removeFailed => '移除异常输出并继续',
    };

List<WorkflowConditionCase> _legacyConditionCases(WorkflowNode node) {
  final expression = node.stringSetting(WorkflowSettingKeys.expression).trim();
  final match = RegExp(
    r'^(.+?)\s*(==|!=|>=|<=|>|<|contains)\s*(.+)$',
  ).firstMatch(expression);
  final operator = switch (match?.group(2)) {
    '!=' => WorkflowConditionOperator.notEquals,
    '>' => WorkflowConditionOperator.greaterThan,
    '<' => WorkflowConditionOperator.lessThan,
    '>=' => WorkflowConditionOperator.greaterThanOrEqual,
    '<=' => WorkflowConditionOperator.lessThanOrEqual,
    'contains' => WorkflowConditionOperator.contains,
    _ => WorkflowConditionOperator.equals,
  };
  return <WorkflowConditionCase>[
    WorkflowConditionCase(
      id: '${node.id}-if',
      conditions: <WorkflowConditionClause>[
        WorkflowConditionClause(
          id: '${node.id}-condition',
          variable: match?.group(1)?.trim() ?? '',
          operator: operator,
          value: match?.group(3)?.trim() ?? '',
        ),
      ],
    ),
  ];
}

({String label, String description, IconData icon, Color color})
workflowNodeDescriptor(WorkflowNodeKind kind, ColorScheme colors) {
  return switch (kind) {
    WorkflowNodeKind.start => (
      label: '开始',
      description: '定义工作流的输入参数',
      icon: Icons.play_arrow_rounded,
      color: colors.primary,
    ),
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
    WorkflowNodeKind.end => (
      label: '结束',
      description: '定义工作流的输出参数',
      icon: Icons.stop_rounded,
      color: colors.tertiary,
    ),
  };
}

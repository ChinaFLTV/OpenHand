import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../app/state/settings_controller.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/motion_durations.dart';
import '../../../shared/ui/motion_preference.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_form_fields.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../../ai/index.dart';
import '../../instructions/index.dart';
import '../../knowledge_base/index.dart';
import '../../mcp/index.dart';
import '../../memory/index.dart';
import '../../skills/index.dart';
import '../model/workflow_definition.dart';
import '../service/workflow_node_executor.dart';
import 'workflow_node_configuration_panel.dart';

const double _canvasWidth = 2400;
const double _canvasHeight = 1600;
const double _nodeWidth = 246;
const double _nodeHeight = 130;
const double _paletteWidth = 92;
const double _configurationWidth = 440;

Future<WorkflowDefinition?> showWorkflowEditorDialog(
  BuildContext context, {
  WorkflowDefinition? workflow,
}) {
  final settings = context.read<SettingsController>();
  final sessions = context.read<AiSessionController>();
  final skills = context.read<SkillsController>();
  final memories = context.read<MemoryController>();
  final instructions = context.read<InstructionsController>();
  final knowledge = context.read<KnowledgeBaseController>();
  final mcp = context.read<McpController>();
  final catalog = WorkflowEditorCatalog(
    models: settings.aiModels,
    templates: sessions.availableTemplates,
    skills: skills.skills,
    memories: memories.entries,
    instructions: instructions.entries,
    knowledgeSources: knowledge.sources,
    mcpServers: mcp.runtimeServers,
  );
  return showAnimatedDialog<WorkflowDefinition>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      final viewport = MediaQuery.sizeOf(dialogContext);
      return buildOpenHandDialog(
        width: math.max(640, viewport.width - 28),
        height: math.max(560, viewport.height - 28),
        insetPadding: const EdgeInsets.all(14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kOpenHandDialogDefaultRadius),
        ),
        child: WorkflowEditorDialog(
          workflow: workflow,
          catalog: catalog,
          templateRepository: sessions.templateRepository,
          knowledgeBaseController: knowledge,
          mcpController: mcp,
        ),
      );
    },
  );
}

class WorkflowEditorDialog extends StatefulWidget {
  const WorkflowEditorDialog({
    super.key,
    required this.catalog,
    required this.templateRepository,
    this.workflow,
    this.knowledgeBaseController,
    this.mcpController,
  });

  final WorkflowDefinition? workflow;
  final WorkflowEditorCatalog catalog;
  final AiPromptTemplateRepository templateRepository;
  final KnowledgeBaseController? knowledgeBaseController;
  final McpController? mcpController;

  @override
  State<WorkflowEditorDialog> createState() => _WorkflowEditorDialogState();
}

class _WorkflowEditorDialogState extends State<WorkflowEditorDialog> {
  static const Uuid _uuid = Uuid();

  late final WorkflowNodeExecutor _executor = WorkflowNodeExecutor();
  late final TransformationController _transformationController =
      TransformationController();
  late final TextEditingController _nameController = TextEditingController(
    text: widget.workflow?.name ?? '',
  );
  late final String _workflowId = widget.workflow?.id ?? _uuid.v4();
  late final DateTime _createdAt =
      widget.workflow?.createdAt ?? DateTime.now().toUtc();
  late List<WorkflowNode> _nodes = List<WorkflowNode>.from(
    widget.workflow?.nodes ?? const <WorkflowNode>[],
  );
  late List<WorkflowConnection> _connections = List<WorkflowConnection>.from(
    widget.workflow?.connections ?? const <WorkflowConnection>[],
  );
  String? _selectedNodeId;
  String? _connectionSourceId;
  bool _testing = false;
  String? _testResult;
  String? _testError;

  WorkflowNode? get _selectedNode {
    final id = _selectedNodeId;
    if (id == null) return null;
    for (final node in _nodes) {
      if (node.id == id) return node;
    }
    return null;
  }

  @override
  void dispose() {
    _executor.dispose();
    _transformationController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: Column(
        children: [
          _buildHeader(context),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final panelWidth = math.min(
                  _configurationWidth,
                  math.max(340.0, constraints.maxWidth * 0.38),
                );
                return Row(
                  children: [
                    _WorkflowNodePalette(onAdd: _addNode),
                    VerticalDivider(
                      width: 1,
                      color: theme.colorScheme.outlineVariant,
                    ),
                    Expanded(child: _buildCanvas(context)),
                    AnimatedContainer(
                      duration: openHandMotionDuration(
                        context,
                        kOpenHandMotion260,
                      ),
                      curve: Curves.easeOutCubic,
                      width: _selectedNode == null ? 0 : panelWidth,
                      clipBehavior: Clip.hardEdge,
                      decoration: const BoxDecoration(),
                      child: _selectedNode == null
                          ? const SizedBox.shrink()
                          : SizedBox(
                              width: panelWidth,
                              child: WorkflowNodeConfigurationPanel(
                                node: _selectedNode!,
                                catalog: widget.catalog,
                                onChanged: _updateNode,
                                onClose: () => setState(() {
                                  _selectedNodeId = null;
                                  _connectionSourceId = null;
                                }),
                                onDelete: _deleteSelectedNode,
                                onTest: _testSelectedNode,
                                testing: _testing,
                                testResult: _testResult,
                                testError: _testError,
                              ),
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 12, 12),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: <Color>[
                    theme.colorScheme.primary,
                    theme.colorScheme.tertiary,
                  ],
                ),
                borderRadius: BorderRadius.circular(kOpenHandRadius12),
              ),
              child: Icon(
                Icons.account_tree_rounded,
                color: theme.colorScheme.onPrimary,
                size: 22,
              ),
            ),
            kOpenHandHGap12,
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 280),
                  child: TextField(
                    controller: _nameController,
                    maxLength: 80,
                    buildCounter: openHandHiddenTextFieldCounter,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                    decoration: const InputDecoration(
                      hintText: '未命名工作流',
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
              ),
            ),
            if (constraints.maxWidth >= 900) ...[
              kOpenHandHGap12,
              _StatusPill(
                icon: Icons.cloud_done_outlined,
                label: widget.workflow == null ? '新建草稿' : '编辑草稿',
              ),
            ],
            if (constraints.maxWidth >= 720) ...[
              kOpenHandHGap10,
              OutlinedButton.icon(
                onPressed: _testing || _selectedNode == null
                    ? null
                    : _testSelectedNode,
                icon: _testing
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow_rounded),
                label: const Text('测试节点'),
              ),
            ],
            kOpenHandHGap10,
            OpenHandDialogActionButton.primary(
              onPressed: _save,
              label: '保存工作流',
              icon: Icons.save_rounded,
            ),
            kOpenHandHGap8,
            IconButton(
              tooltip: '关闭',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCanvas(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() {
              _selectedNodeId = null;
              _connectionSourceId = null;
            }),
            child: InteractiveViewer(
              transformationController: _transformationController,
              constrained: false,
              minScale: 0.35,
              maxScale: 2.2,
              boundaryMargin: const EdgeInsets.all(320),
              child: SizedBox(
                width: _canvasWidth,
                height: _canvasHeight,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _WorkflowGridPainter(
                          color: theme.colorScheme.outlineVariant,
                          majorColor: theme.colorScheme.outline,
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _WorkflowConnectionPainter(
                            nodes: _nodes,
                            connections: _connections,
                            color: theme.colorScheme.primary,
                            mutedColor: theme.colorScheme.outline,
                          ),
                        ),
                      ),
                    ),
                    for (final node in _nodes) _buildNodeCard(context, node),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_nodes.isEmpty)
          Center(
            child: _CanvasEmptyState(
              onAddLlm: () => _addNode(WorkflowNodeKind.llm),
            ),
          ),
        if (_connectionSourceId != null)
          const Positioned(
            top: 14,
            left: 16,
            child: _StatusPill(
              icon: Icons.link_rounded,
              label: '请选择目标节点，按 Esc 或点击空白处取消',
              emphasized: true,
            ),
          ),
        Positioned(
          right: 16,
          bottom: 16,
          child: _CanvasToolbar(
            scale: _transformationController.value.getMaxScaleOnAxis(),
            canConnect: _selectedNode != null,
            connecting: _connectionSourceId != null,
            canDelete: _selectedNode != null,
            onZoomIn: () => _changeZoom(0.15),
            onZoomOut: () => _changeZoom(-0.15),
            onReset: _resetViewport,
            onConnect: _startConnection,
            onDelete: _deleteSelectedNode,
          ),
        ),
      ],
    );
  }

  Widget _buildNodeCard(BuildContext context, WorkflowNode node) {
    final selected = node.id == _selectedNodeId;
    final source = node.id == _connectionSourceId;
    final theme = Theme.of(context);
    final descriptor = workflowNodeDescriptor(node.kind, theme.colorScheme);
    return Positioned(
      left: node.x,
      top: node.y,
      width: _nodeWidth,
      height: _nodeHeight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (_connectionSourceId != null && _connectionSourceId != node.id) {
            _finishConnection(node.id);
            return;
          }
          setState(() {
            _selectedNodeId = node.id;
            _testResult = null;
            _testError = null;
          });
        },
        onPanUpdate: (details) {
          final scale = math.max(
            0.35,
            _transformationController.value.getMaxScaleOnAxis(),
          );
          _updateNode(
            node.copyWith(
              x: (node.x + details.delta.dx / scale).clamp(
                16,
                _canvasWidth - _nodeWidth - 16,
              ),
              y: (node.y + details.delta.dy / scale).clamp(
                16,
                _canvasHeight - _nodeHeight - 16,
              ),
            ),
          );
        },
        child: AnimatedContainer(
          duration: openHandMotionDuration(context, kOpenHandMotion180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.38)
                : theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(kOpenHandRadius18),
            border: Border.all(
              color: selected || source
                  ? descriptor.color
                  : theme.colorScheme.outlineVariant,
              width: selected || source ? 2 : 1,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: theme.colorScheme.shadow.withValues(
                  alpha: selected ? 0.18 : 0.09,
                ),
                blurRadius: selected ? 24 : 14,
                offset: const Offset(0, 7),
              ),
            ],
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
                      color: descriptor.color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(kOpenHandRadius10),
                    ),
                    child: Icon(
                      descriptor.icon,
                      color: descriptor.color,
                      size: 19,
                    ),
                  ),
                  kOpenHandHGap9,
                  Expanded(
                    child: Text(
                      node.title.trim().isEmpty
                          ? descriptor.label
                          : node.title.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.drag_indicator_rounded,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              kOpenHandGap12,
              Text(
                _nodeSummary(node),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  height: 1.4,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.colorScheme.outline,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    descriptor.label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: descriptor.color,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  kOpenHandHGap6,
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: descriptor.color,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _addNode(WorkflowNodeKind kind) {
    final descriptor = workflowNodeDescriptor(
      kind,
      Theme.of(context).colorScheme,
    );
    final index = _nodes.length;
    final node = WorkflowNode(
      id: _uuid.v4(),
      kind: kind,
      title: descriptor.label,
      x: 300 + (index % 4) * 285,
      y: 180 + (index ~/ 4) * 185,
      settings: _defaultSettings(kind),
    );
    setState(() {
      _nodes = <WorkflowNode>[..._nodes, node];
      _selectedNodeId = node.id;
      _connectionSourceId = null;
      _testResult = null;
      _testError = null;
    });
  }

  Map<String, Object?> _defaultSettings(WorkflowNodeKind kind) {
    return switch (kind) {
      WorkflowNodeKind.condition => <String, Object?>{
        WorkflowSettingKeys.expression: '{{status}} == success',
      },
      WorkflowNodeKind.loop => <String, Object?>{
        WorkflowSettingKeys.maxIterations: 10,
      },
      WorkflowNodeKind.iteration => <String, Object?>{
        WorkflowSettingKeys.iterationInput: 'items',
      },
      WorkflowNodeKind.llm => <String, Object?>{
        WorkflowSettingKeys.modelConfigId:
            widget.catalog.models.firstOrNull?.id ?? '',
        WorkflowSettingKeys.templateId:
            widget.catalog.templates
                .where((item) => item.id == 'default')
                .firstOrNull
                ?.id ??
            widget.catalog.templates.firstOrNull?.id ??
            '',
        WorkflowSettingKeys.prompt: '',
        WorkflowSettingKeys.multimodalCapabilities: <String>[],
        WorkflowSettingKeys.skillNames: <String>[],
        WorkflowSettingKeys.memoryIds: <String>[],
        WorkflowSettingKeys.instructionIds: <String>[],
        WorkflowSettingKeys.knowledgeSourceIds: <String>[],
        WorkflowSettingKeys.mcpServerNames: <String>[],
        WorkflowSettingKeys.structuredOutput: false,
        WorkflowSettingKeys.outputFields: <Object?>[],
        WorkflowSettingKeys.retryCount: 0,
        WorkflowSettingKeys.retryIntervalMs: 1000,
      },
      WorkflowNodeKind.httpRequest => <String, Object?>{
        WorkflowSettingKeys.url: '',
        WorkflowSettingKeys.method: 'GET',
        WorkflowSettingKeys.headers: <Object?>[],
        WorkflowSettingKeys.queryParameters: <Object?>[],
        WorkflowSettingKeys.body: '',
        WorkflowSettingKeys.bodyEntries: <Object?>[],
        WorkflowSettingKeys.bodyFormat:
            WorkflowHttpBodyFormat.none.storageValue,
        WorkflowSettingKeys.connectTimeoutSeconds: 15,
        WorkflowSettingKeys.responseTimeoutSeconds: 60,
        WorkflowSettingKeys.structuredOutput: false,
        WorkflowSettingKeys.outputFields: <Object?>[],
        WorkflowSettingKeys.retryCount: 0,
        WorkflowSettingKeys.retryIntervalMs: 1000,
      },
    };
  }

  void _updateNode(WorkflowNode updated) {
    if (!mounted) return;
    setState(() {
      _nodes = _nodes
          .map((node) => node.id == updated.id ? updated : node)
          .toList(growable: false);
      if (_selectedNodeId == updated.id) {
        _testResult = null;
        _testError = null;
      }
    });
  }

  void _deleteSelectedNode() {
    final id = _selectedNodeId;
    if (id == null) return;
    setState(() {
      _nodes = _nodes.where((node) => node.id != id).toList(growable: false);
      _connections = _connections
          .where((edge) => edge.sourceNodeId != id && edge.targetNodeId != id)
          .toList(growable: false);
      _selectedNodeId = null;
      if (_connectionSourceId == id) _connectionSourceId = null;
      _testResult = null;
      _testError = null;
    });
  }

  void _startConnection() {
    final id = _selectedNodeId;
    if (id == null) return;
    setState(() => _connectionSourceId = _connectionSourceId == id ? null : id);
  }

  void _finishConnection(String targetNodeId) {
    final sourceNodeId = _connectionSourceId;
    if (sourceNodeId == null || sourceNodeId == targetNodeId) return;
    final duplicate = _connections.any(
      (edge) =>
          edge.sourceNodeId == sourceNodeId &&
          edge.targetNodeId == targetNodeId,
    );
    setState(() {
      if (!duplicate) {
        _connections = <WorkflowConnection>[
          ..._connections,
          WorkflowConnection(
            id: _uuid.v4(),
            sourceNodeId: sourceNodeId,
            targetNodeId: targetNodeId,
          ),
        ];
      }
      _selectedNodeId = targetNodeId;
      _connectionSourceId = null;
    });
  }

  Future<void> _testSelectedNode() async {
    final node = _selectedNode;
    if (node == null || _testing) return;
    setState(() {
      _testing = true;
      _testResult = null;
      _testError = null;
    });
    try {
      final mcpController = widget.mcpController;
      final mcpTools = <String, List<McpTool>>{
        if (mcpController != null)
          for (final server in widget.catalog.mcpServers)
            server.name: mcpController.toolCatalogFor(server.name).tools,
      };
      final result = await _executor.execute(
        node: node,
        resources: WorkflowExecutionResources(
          models: widget.catalog.models,
          templateRepository: widget.templateRepository,
          skills: widget.catalog.skills,
          memories: widget.catalog.memories,
          instructions: widget.catalog.instructions,
          knowledgeBaseController: widget.knowledgeBaseController,
          mcpServers: widget.catalog.mcpServers,
          mcpTools: mcpTools,
          mcpToolInvoker: mcpController == null
              ? null
              : ({
                  required serverName,
                  required toolName,
                  required arguments,
                  required toolCallId,
                }) async {
                  final result = await mcpController.callTool(
                    serverName: serverName,
                    toolName: toolName,
                    arguments: arguments,
                    toolCallId: toolCallId,
                  );
                  return WorkflowMcpToolInvocationResult(
                    output: result.outputText,
                    isError: result.isError,
                  );
                },
        ),
        variables: <String, Object?>{
          'input': '测试输入',
          'status': 'success',
          'value': 'demo',
          'items': <Object?>['第一项', '第二项'],
        },
      );
      if (!mounted) return;
      setState(() {
        _testResult = _formatExecutionResult(result);
        _testError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _testResult = null;
        _testError = '$error';
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  void _save() {
    final name = _nameController.text.trim();
    final error = _validate(name);
    if (error != null) {
      showOpenHandInfoSnack(context, error);
      return;
    }
    Navigator.of(context).pop(
      WorkflowDefinition(
        id: _workflowId,
        name: name,
        createdAt: _createdAt,
        updatedAt: DateTime.now().toUtc(),
        nodes: List<WorkflowNode>.unmodifiable(_nodes),
        connections: List<WorkflowConnection>.unmodifiable(_connections),
      ),
    );
  }

  String? _validate(String name) {
    if (name.isEmpty) return '请输入工作流名称。';
    if (_nodes.isEmpty) return '请至少添加一个节点。';
    for (final node in _nodes) {
      if (node.title.trim().isEmpty) return '节点名称不能为空。';
      if (node.kind == WorkflowNodeKind.llm) {
        if (node
            .stringSetting(WorkflowSettingKeys.modelConfigId)
            .trim()
            .isEmpty) {
          return '请为 LLM 节点选择模型。';
        }
        if (node.stringSetting(WorkflowSettingKeys.prompt).trim().isEmpty) {
          return '请填写 LLM 节点提示词。';
        }
      }
      if (node.kind == WorkflowNodeKind.httpRequest &&
          node.stringSetting(WorkflowSettingKeys.url).trim().isEmpty) {
        return '请填写 HTTP 节点请求 URL。';
      }
      if (node.boolSetting(WorkflowSettingKeys.structuredOutput)) {
        try {
          WorkflowStructuredOutputParser.validateFields(node.outputFields());
        } catch (error) {
          return '$error';
        }
      }
    }
    return null;
  }

  void _changeZoom(double delta) {
    final current = _transformationController.value.getMaxScaleOnAxis();
    final next = (current + delta).clamp(0.35, 2.2);
    final matrix = _transformationController.value.clone();
    final factor = next / math.max(0.01, current);
    matrix.scaleByDouble(factor, factor, 1, 1);
    _transformationController.value = matrix;
    setState(() {});
  }

  void _resetViewport() {
    _transformationController.value = Matrix4.identity();
    setState(() {});
  }
}

class _WorkflowNodePalette extends StatelessWidget {
  const _WorkflowNodePalette({required this.onAdd});

  final ValueChanged<WorkflowNodeKind> onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: _paletteWidth,
      child: ColoredBox(
        color: theme.colorScheme.surfaceContainerLow,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 13, 8, 7),
              child: Text(
                '节点',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                children: WorkflowNodeKind.values
                    .map(
                      (kind) =>
                          _PaletteItem(kind: kind, onTap: () => onAdd(kind)),
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

class _PaletteItem extends StatelessWidget {
  const _PaletteItem({required this.kind, required this.onTap});

  final WorkflowNodeKind kind;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final descriptor = workflowNodeDescriptor(kind, theme.colorScheme);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Tooltip(
        message: '${descriptor.label}\n${descriptor.description}',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(kOpenHandRadius12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
              child: Column(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: descriptor.color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(kOpenHandRadius11),
                    ),
                    child: Icon(
                      descriptor.icon,
                      color: descriptor.color,
                      size: 20,
                    ),
                  ),
                  kOpenHandGap5,
                  Text(
                    descriptor.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CanvasEmptyState extends StatelessWidget {
  const _CanvasEmptyState({required this.onAddLlm});

  final VoidCallback onAddLlm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(maxWidth: 380),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(kOpenHandRadius20),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.1),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.schema_rounded,
            size: 42,
            color: theme.colorScheme.primary,
          ),
          kOpenHandGap12,
          Text(
            '搭建第一个节点',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          kOpenHandGap7,
          Text(
            '从左侧选择节点，拖动卡片调整位置，再通过工具栏连接执行路径。',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          kOpenHandGap16,
          FilledButton.icon(
            onPressed: onAddLlm,
            icon: const Icon(Icons.auto_awesome_rounded),
            label: const Text('添加 LLM 节点'),
          ),
        ],
      ),
    );
  }
}

class _CanvasToolbar extends StatelessWidget {
  const _CanvasToolbar({
    required this.scale,
    required this.canConnect,
    required this.connecting,
    required this.canDelete,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onReset,
    required this.onConnect,
    required this.onDelete,
  });

  final double scale;
  final bool canConnect;
  final bool connecting;
  final bool canDelete;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onReset;
  final VoidCallback onConnect;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.96),
      elevation: 7,
      shadowColor: theme.colorScheme.shadow.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(kOpenHandRadius14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ToolbarButton(
              tooltip: '缩小',
              icon: Icons.remove_rounded,
              onPressed: onZoomOut,
            ),
            SizedBox(
              width: 58,
              child: Text(
                '${(scale * 100).round()}%',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            _ToolbarButton(
              tooltip: '放大',
              icon: Icons.add_rounded,
              onPressed: onZoomIn,
            ),
            _ToolbarButton(
              tooltip: '重置视图',
              icon: Icons.center_focus_strong_rounded,
              onPressed: onReset,
            ),
            Container(
              width: 1,
              height: 24,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              color: theme.colorScheme.outlineVariant,
            ),
            _ToolbarButton(
              tooltip: connecting ? '取消连接' : '连接所选节点',
              icon: connecting ? Icons.link_off_rounded : Icons.link_rounded,
              selected: connecting,
              onPressed: canConnect ? onConnect : null,
            ),
            _ToolbarButton(
              tooltip: '删除所选节点',
              icon: Icons.delete_outline_rounded,
              onPressed: canDelete ? onDelete : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.selected = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 19),
        style: IconButton.styleFrom(
          backgroundColor: selected
              ? Theme.of(context).colorScheme.primaryContainer
              : Colors.transparent,
          minimumSize: const Size.square(36),
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.icon,
    required this.label,
    this.emphasized = false,
  });

  final IconData icon;
  final String label;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: emphasized
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: emphasized
              ? theme.colorScheme.primary.withValues(alpha: 0.35)
              : theme.colorScheme.outlineVariant,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: theme.colorScheme.primary),
          kOpenHandHGap6,
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkflowGridPainter extends CustomPainter {
  const _WorkflowGridPainter({required this.color, required this.majorColor});

  final Color color;
  final Color majorColor;

  @override
  void paint(Canvas canvas, Size size) {
    const minor = 24.0;
    const major = 120.0;
    final dotPaint = Paint()..color = color.withValues(alpha: 0.46);
    final majorPaint = Paint()..color = majorColor.withValues(alpha: 0.35);
    for (var x = 0.0; x <= size.width; x += minor) {
      for (var y = 0.0; y <= size.height; y += minor) {
        final isMajor = x % major == 0 && y % major == 0;
        canvas.drawCircle(
          Offset(x, y),
          isMajor ? 1.45 : 0.8,
          isMajor ? majorPaint : dotPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_WorkflowGridPainter oldDelegate) {
    return color != oldDelegate.color || majorColor != oldDelegate.majorColor;
  }
}

class _WorkflowConnectionPainter extends CustomPainter {
  const _WorkflowConnectionPainter({
    required this.nodes,
    required this.connections,
    required this.color,
    required this.mutedColor,
  });

  final List<WorkflowNode> nodes;
  final List<WorkflowConnection> connections;
  final Color color;
  final Color mutedColor;

  @override
  void paint(Canvas canvas, Size size) {
    final byId = <String, WorkflowNode>{
      for (final node in nodes) node.id: node,
    };
    final linePaint = Paint()
      ..color = color.withValues(alpha: 0.72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    final haloPaint = Paint()
      ..color = mutedColor.withValues(alpha: 0.16)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7;
    for (final edge in connections) {
      final source = byId[edge.sourceNodeId];
      final target = byId[edge.targetNodeId];
      if (source == null || target == null) continue;
      final start = Offset(source.x + _nodeWidth, source.y + _nodeHeight / 2);
      final end = Offset(target.x, target.y + _nodeHeight / 2);
      final distance = math.max(70, (end.dx - start.dx).abs() * 0.46);
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(
          start.dx + distance,
          start.dy,
          end.dx - distance,
          end.dy,
          end.dx,
          end.dy,
        );
      canvas.drawPath(path, haloPaint);
      canvas.drawPath(path, linePaint);
      final angle = math.atan2(end.dy - (end.dy), end.dx - (end.dx - distance));
      final arrow = Path()
        ..moveTo(end.dx, end.dy)
        ..lineTo(
          end.dx - 9 * math.cos(angle - math.pi / 6),
          end.dy - 9 * math.sin(angle - math.pi / 6),
        )
        ..moveTo(end.dx, end.dy)
        ..lineTo(
          end.dx - 9 * math.cos(angle + math.pi / 6),
          end.dy - 9 * math.sin(angle + math.pi / 6),
        );
      canvas.drawPath(arrow, linePaint);
    }
  }

  @override
  bool shouldRepaint(_WorkflowConnectionPainter oldDelegate) {
    return nodes != oldDelegate.nodes ||
        connections != oldDelegate.connections ||
        color != oldDelegate.color ||
        mutedColor != oldDelegate.mutedColor;
  }
}

String _nodeSummary(WorkflowNode node) {
  return switch (node.kind) {
    WorkflowNodeKind.llm =>
      node.stringSetting(WorkflowSettingKeys.prompt).trim().isEmpty
          ? '选择模型并编写提示词'
          : node.stringSetting(WorkflowSettingKeys.prompt).trim(),
    WorkflowNodeKind.httpRequest =>
      node.stringSetting(WorkflowSettingKeys.url).trim().isEmpty
          ? '配置请求方式、URL 与响应输出'
          : '${node.stringSetting(WorkflowSettingKeys.method, 'GET')}  ${node.stringSetting(WorkflowSettingKeys.url)}',
    WorkflowNodeKind.condition => node.stringSetting(
      WorkflowSettingKeys.expression,
    ),
    WorkflowNodeKind.loop =>
      '最多循环 ${node.intSetting(WorkflowSettingKeys.maxIterations, 10)} 次',
    WorkflowNodeKind.iteration =>
      '迭代数组变量 ${node.stringSetting(WorkflowSettingKeys.iterationInput, 'items')}',
  };
}

String _formatExecutionResult(WorkflowNodeExecutionResult result) {
  final output = result.output;
  final formatted = output is String
      ? output
      : const JsonEncoder.withIndent('  ').convert(output);
  return '尝试 ${result.attempts} 次 · ${result.duration.inMilliseconds} 毫秒\n\n$formatted';
}

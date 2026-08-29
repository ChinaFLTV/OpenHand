import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../app/state/settings_controller.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/animated_menu.dart';
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
const double _nodeAddButtonSize = 26;
const double _nodeAddButtonHitSize = 38;
const double _configurationWidth = 440;
const double _headerActionSize = 44;
const int _maxWorkflowHistoryEntries = 80;
const Duration _workflowHistoryMergeWindow = Duration(milliseconds: 900);
const RoundedRectangleBorder _workflowButtonShape = RoundedRectangleBorder(
  borderRadius: kOpenHandBorderRadius12,
);

class _WorkflowGraphSnapshot {
  const _WorkflowGraphSnapshot({
    required this.nodes,
    required this.connections,
  });

  final List<WorkflowNode> nodes;
  final List<WorkflowConnection> connections;
}

class _WorkflowHistoryEntry {
  const _WorkflowHistoryEntry({
    required this.label,
    required this.createdAt,
    required this.snapshot,
    this.mergeKey,
  });

  final String label;
  final DateTime createdAt;
  final _WorkflowGraphSnapshot snapshot;
  final String? mergeKey;
}

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
    recentModelSelections: settings.recentModelSelections,
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
  late final FocusNode _canvasFocusNode = FocusNode(
    debugLabel: 'workflow-canvas',
  );
  final GlobalKey _canvasSurfaceKey = GlobalKey();
  late String _workflowName = widget.workflow?.name ?? '';
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
  String? _selectedConnectionId;
  bool _testing = false;
  String? _testResult;
  String? _testError;
  WorkflowNodeTestStatus? _testStatus;
  String? _connectingSourceNodeId;
  String? _connectionTargetNodeId;
  String? _connectionTargetError;
  Offset? _connectionDragPosition;
  late final List<_WorkflowHistoryEntry> _history;
  int _historyIndex = 0;

  WorkflowNode? get _selectedNode {
    final id = _selectedNodeId;
    if (id == null) return null;
    for (final node in _nodes) {
      if (node.id == id) return node;
    }
    return null;
  }

  bool get _canUndo => _historyIndex > 0;
  bool get _canRedo => _historyIndex + 1 < _history.length;

  @override
  void initState() {
    super.initState();
    _history = <_WorkflowHistoryEntry>[
      _WorkflowHistoryEntry(
        label: widget.workflow == null ? '创建工作流' : '打开工作流',
        createdAt: DateTime.now(),
        snapshot: _currentSnapshot(),
      ),
    ];
  }

  @override
  void dispose() {
    _executor.dispose();
    _transformationController.dispose();
    _canvasFocusNode.dispose();
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
                          : OverflowBox(
                              alignment: Alignment.centerLeft,
                              minWidth: panelWidth,
                              maxWidth: panelWidth,
                              child: WorkflowNodeConfigurationPanel(
                                node: _selectedNode!,
                                catalog: widget.catalog,
                                availableReferences: _availableReferencesFor(
                                  _selectedNode!,
                                ),
                                reservedParameterNames:
                                    _reservedParameterNamesFor(_selectedNode!),
                                onChanged: _updateNode,
                                onClose: () => setState(() {
                                  _selectedNodeId = null;
                                }),
                                onDelete: _deleteSelectedNode,
                                onTest: _testSelectedNode,
                                testing: _testing,
                                testResult: _testResult,
                                testError: _testError,
                                testStatus: _testStatus,
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
    final actionStyle = IconButton.styleFrom(
      fixedSize: const Size.square(_headerActionSize),
      padding: EdgeInsets.zero,
      shape: _workflowButtonShape,
      shadowColor: Colors.transparent,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 12, 12),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(kOpenHandRadius12),
            ),
            child: Icon(
              Icons.account_tree_rounded,
              color: theme.colorScheme.onPrimaryContainer,
              size: 22,
            ),
          ),
          kOpenHandHGap12,
          Expanded(
            child: Text(
              '新建工作流',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          IconButton.filledTonal(
            tooltip: '保存工作流',
            onPressed: _save,
            style: actionStyle,
            icon: const Icon(Icons.save_rounded),
          ),
          kOpenHandHGap8,
          IconButton.filledTonal(
            tooltip: '关闭',
            onPressed: () => Navigator.of(context).pop(),
            style: actionStyle,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildCanvas(BuildContext context) {
    final theme = Theme.of(context);
    return Focus(
      focusNode: _canvasFocusNode,
      onKeyEvent: _handleCanvasKeyEvent,
      child: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              transformationController: _transformationController,
              constrained: false,
              panEnabled: _connectingSourceNodeId == null,
              scaleEnabled: _connectingSourceNodeId == null,
              minScale: 0.35,
              maxScale: 2.2,
              boundaryMargin: const EdgeInsets.all(320),
              child: SizedBox(
                key: _canvasSurfaceKey,
                width: _canvasWidth,
                height: _canvasHeight,
                child: Stack(
                  clipBehavior: Clip.none,
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
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (details) =>
                            _selectCanvasAt(details.localPosition),
                        child: CustomPaint(
                          painter: _WorkflowConnectionPainter(
                            nodes: _nodes,
                            connections: _connections,
                            selectedConnectionId: _selectedConnectionId,
                            draftSourceNodeId: _connectingSourceNodeId,
                            draftTargetNodeId: _connectionTargetNodeId,
                            draftEnd: _connectionDragPosition,
                            draftValid:
                                _connectionTargetNodeId != null &&
                                _connectionTargetError == null,
                            color: theme.colorScheme.primary,
                            errorColor: theme.colorScheme.error,
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
          if (_nodes.isEmpty)
            Center(
              child: _CanvasEmptyState(
                onAddStart: () => _addNode(WorkflowNodeKind.start),
              ),
            ),
          Positioned(
            right: 16,
            bottom: 16,
            child: _CanvasToolbar(
              scale: _transformationController.value.getMaxScaleOnAxis(),
              canDelete:
                  _selectedNodeId != null || _selectedConnectionId != null,
              onZoomIn: () => _changeZoom(0.15),
              onZoomOut: () => _changeZoom(-0.15),
              onReset: _resetViewport,
              onDelete: _deleteSelection,
              canUndo: _canUndo,
              canRedo: _canRedo,
              history: _history,
              historyIndex: _historyIndex,
              onUndo: _undo,
              onRedo: _redo,
              onHistorySelected: _restoreHistory,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNodeCard(BuildContext context, WorkflowNode node) {
    final selected = node.id == _selectedNodeId;
    final connectionTarget = node.id == _connectionTargetNodeId;
    final connectionTargetValid =
        connectionTarget && _connectionTargetError == null;
    final theme = Theme.of(context);
    final descriptor = workflowNodeDescriptor(node.kind, theme.colorScheme);
    return Positioned(
      left: node.x,
      top: node.y,
      width: _nodeWidth + _nodeAddButtonHitSize / 2,
      height: _nodeHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 0,
            width: _nodeWidth,
            height: _nodeHeight,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _selectNode(node.id),
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
                  historyLabel: '移动节点',
                  mergeKey: 'move:${node.id}',
                );
              },
              child: AnimatedScale(
                scale: connectionTarget ? 1.015 : 1,
                duration: openHandMotionDuration(context, kOpenHandMotion180),
                curve: Curves.easeOutCubic,
                child: AnimatedContainer(
                  duration: openHandMotionDuration(context, kOpenHandMotion180),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: connectionTarget
                        ? (connectionTargetValid
                              ? theme.colorScheme.primaryContainer.withValues(
                                  alpha: 0.46,
                                )
                              : theme.colorScheme.errorContainer.withValues(
                                  alpha: 0.34,
                                ))
                        : selected
                        ? theme.colorScheme.primaryContainer.withValues(
                            alpha: 0.38,
                          )
                        : theme.colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(kOpenHandRadius18),
                    border: Border.all(
                      color: connectionTarget
                          ? (connectionTargetValid
                                ? theme.colorScheme.primary
                                : theme.colorScheme.error)
                          : selected
                          ? descriptor.color
                          : theme.colorScheme.outlineVariant,
                      width: connectionTarget || selected ? 2 : 1,
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color:
                            (connectionTarget
                                    ? (connectionTargetValid
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.error)
                                    : theme.colorScheme.shadow)
                                .withValues(
                                  alpha: connectionTarget
                                      ? 0.2
                                      : selected
                                      ? 0.18
                                      : 0.09,
                                ),
                        blurRadius: connectionTarget || selected ? 24 : 14,
                        offset: const Offset(0, 7),
                      ),
                    ],
                  ),
                  child: _buildNodeCardContent(
                    context,
                    node,
                    descriptor,
                    connectionTarget: connectionTarget,
                    connectionTargetValid: connectionTargetValid,
                  ),
                ),
              ),
            ),
          ),
          if (node.kind != WorkflowNodeKind.end)
            Positioned(
              left: _nodeWidth - _nodeAddButtonHitSize / 2,
              top: (_nodeHeight - _nodeAddButtonHitSize) / 2,
              child: _buildAddNodeButton(context, node),
            ),
        ],
      ),
    );
  }

  Widget _buildNodeCardContent(
    BuildContext context,
    WorkflowNode node,
    ({String label, String description, IconData icon, Color color})
    descriptor, {
    required bool connectionTarget,
    required bool connectionTargetValid,
  }) {
    final theme = Theme.of(context);
    return Column(
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
              child: Icon(descriptor.icon, color: descriptor.color, size: 19),
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
            if (node.kind != WorkflowNodeKind.start)
              AnimatedContainer(
                duration: openHandMotionDuration(context, kOpenHandMotion180),
                width: connectionTarget ? 10 : 8,
                height: connectionTarget ? 10 : 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: connectionTarget
                      ? (connectionTargetValid
                            ? theme.colorScheme.primary
                            : theme.colorScheme.error)
                      : theme.colorScheme.outline,
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
            if (node.kind != WorkflowNodeKind.end)
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
    );
  }

  Widget _buildAddNodeButton(BuildContext context, WorkflowNode source) {
    final theme = Theme.of(context);
    final connecting = source.id == _connectingSourceNodeId;
    return Tooltip(
      message: '单击添加节点，拖拽连接已有节点',
      child: MouseRegion(
        cursor: connecting
            ? SystemMouseCursors.grabbing
            : SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (details) =>
              _startConnectionDrag(source, details.globalPosition),
          onPanUpdate: (details) =>
              _updateConnectionDrag(details.globalPosition),
          onPanEnd: (_) => _finishConnectionDrag(),
          onPanCancel: _cancelConnectionDrag,
          child: SizedBox.square(
            dimension: _nodeAddButtonHitSize,
            child: Center(
              child: AnimatedScale(
                scale: connecting ? 0.92 : 1,
                duration: openHandMotionDuration(context, kOpenHandMotion120),
                curve: Curves.easeOutCubic,
                child: AnimatedContainer(
                  duration: openHandMotionDuration(context, kOpenHandMotion180),
                  width: _nodeAddButtonSize,
                  height: _nodeAddButtonSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: connecting
                        ? theme.colorScheme.primaryContainer
                        : theme.colorScheme.primary,
                    border: Border.all(
                      color: connecting
                          ? theme.colorScheme.primary
                          : theme.colorScheme.primary.withValues(alpha: 0.7),
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: theme.colorScheme.primary.withValues(
                          alpha: connecting ? 0.28 : 0.18,
                        ),
                        blurRadius: connecting ? 12 : 7,
                      ),
                    ],
                  ),
                  child: Builder(
                    builder: (buttonContext) => Material(
                      color: Colors.transparent,
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => _showAddNodeMenu(buttonContext, source),
                        child: Icon(
                          Icons.add_rounded,
                          size: 17,
                          color: connecting
                              ? theme.colorScheme.onPrimaryContainer
                              : theme.colorScheme.onPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showAddNodeMenu(
    BuildContext buttonContext,
    WorkflowNode source,
  ) async {
    final theme = Theme.of(buttonContext);
    final selected = await showAnimatedAnchoredPopupMenu<WorkflowNodeKind>(
      context: buttonContext,
      offset: const Offset(18, 0),
      constraints: const BoxConstraints(minWidth: 260, maxWidth: 300),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kOpenHandRadius14),
      ),
      items: WorkflowNodeKind.values
          .where((kind) => kind != WorkflowNodeKind.start)
          .map((kind) {
            final descriptor = workflowNodeDescriptor(kind, theme.colorScheme);
            return PopupMenuItem<WorkflowNodeKind>(
              value: kind,
              height: 58,
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: descriptor.color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(kOpenHandRadius10),
                    ),
                    child: Icon(
                      descriptor.icon,
                      color: descriptor.color,
                      size: 19,
                    ),
                  ),
                  kOpenHandHGap10,
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          descriptor.label,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        kOpenHandGap2,
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
                ],
              ),
            );
          })
          .toList(growable: false),
    );
    if (!mounted || selected == null) return;
    final latestSource = _nodes
        .where((node) => node.id == source.id)
        .firstOrNull;
    if (latestSource != null) _addConnectedNode(latestSource, selected);
  }

  void _startConnectionDrag(WorkflowNode source, Offset globalPosition) {
    if (source.kind == WorkflowNodeKind.end ||
        !_nodes.any((node) => node.id == source.id)) {
      return;
    }
    final position = _canvasPosition(globalPosition);
    if (position == null) return;
    setState(() {
      _connectingSourceNodeId = source.id;
      _connectionDragPosition = position;
      _connectionTargetNodeId = null;
      _connectionTargetError = null;
      _selectedConnectionId = null;
    });
  }

  void _updateConnectionDrag(Offset globalPosition) {
    final sourceId = _connectingSourceNodeId;
    if (sourceId == null) return;
    final position = _canvasPosition(globalPosition);
    if (position == null) return;
    final target = _nodeAtPosition(position, excludingNodeId: sourceId);
    final source = _nodes.where((node) => node.id == sourceId).firstOrNull;
    setState(() {
      _connectionDragPosition = position;
      _connectionTargetNodeId = target?.id;
      _connectionTargetError = source == null || target == null
          ? null
          : _connectionError(source, target);
    });
  }

  void _finishConnectionDrag() {
    final source = _nodes
        .where((node) => node.id == _connectingSourceNodeId)
        .firstOrNull;
    final target = _nodes
        .where((node) => node.id == _connectionTargetNodeId)
        .firstOrNull;
    final error = source == null || target == null
        ? null
        : _connectionError(source, target);
    if (source == null || target == null || error != null) {
      _cancelConnectionDrag();
      if (error != null && mounted) showOpenHandInfoSnack(context, error);
      return;
    }

    final connection = WorkflowConnection(
      id: _uuid.v4(),
      sourceNodeId: source.id,
      targetNodeId: target.id,
    );
    setState(() {
      _clearConnectionDragState();
      _connections = <WorkflowConnection>[..._connections, connection];
      _selectedNodeId = null;
      _selectedConnectionId = connection.id;
      _testResult = null;
      _testError = null;
      _testStatus = null;
      _recordHistory('连接${source.title.trim()}与${target.title.trim()}节点');
    });
    _canvasFocusNode.requestFocus();
  }

  void _cancelConnectionDrag() {
    if (_connectingSourceNodeId == null && _connectionDragPosition == null) {
      return;
    }
    setState(_clearConnectionDragState);
  }

  void _clearConnectionDragState() {
    _connectingSourceNodeId = null;
    _connectionTargetNodeId = null;
    _connectionTargetError = null;
    _connectionDragPosition = null;
  }

  Offset? _canvasPosition(Offset globalPosition) {
    final renderObject =
        _canvasSurfaceKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderObject == null || !renderObject.hasSize) return null;
    final local = renderObject.globalToLocal(globalPosition);
    return Offset(
      local.dx.clamp(0, _canvasWidth),
      local.dy.clamp(0, _canvasHeight),
    );
  }

  WorkflowNode? _nodeAtPosition(
    Offset position, {
    required String excludingNodeId,
  }) {
    for (final node in _nodes.reversed) {
      if (node.id == excludingNodeId) continue;
      final bounds = Rect.fromLTWH(
        node.x,
        node.y,
        _nodeWidth,
        _nodeHeight,
      ).inflate(8);
      if (bounds.contains(position)) return node;
    }
    return null;
  }

  String? _connectionError(WorkflowNode source, WorkflowNode target) {
    if (source.id == target.id) return '节点不能连接到自身。';
    if (source.kind == WorkflowNodeKind.end) return '结束节点不能连接后续节点。';
    if (target.kind == WorkflowNodeKind.start) return '开始节点不能作为后续节点。';
    if (_connections.any(
      (connection) =>
          connection.sourceNodeId == source.id &&
          connection.targetNodeId == target.id,
    )) {
      return '这两个节点已经连接。';
    }
    if (_wouldCreateConnectionCycle(source.id, target.id)) {
      return '该连接会形成循环，请调整节点方向。';
    }
    return null;
  }

  bool _wouldCreateConnectionCycle(String sourceId, String targetId) {
    final visited = <String>{};
    final pending = <String>[targetId];
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      if (current == sourceId) return true;
      if (!visited.add(current)) continue;
      for (final connection in _connections) {
        if (connection.sourceNodeId == current) {
          pending.add(connection.targetNodeId);
        }
      }
    }
    return false;
  }

  void _addNode(WorkflowNodeKind kind) {
    final hasStart = _nodes.any((node) => node.kind == WorkflowNodeKind.start);
    if (!hasStart && kind != WorkflowNodeKind.start) {
      showOpenHandInfoSnack(context, '请先添加开始节点。');
      return;
    }
    if (hasStart && kind == WorkflowNodeKind.start) {
      showOpenHandInfoSnack(context, '工作流只能包含一个开始节点。');
      return;
    }
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
      _selectedConnectionId = null;
      _testResult = null;
      _testError = null;
      _testStatus = null;
      _recordHistory('添加${descriptor.label}节点');
    });
    _canvasFocusNode.requestFocus();
  }

  void _addConnectedNode(WorkflowNode source, WorkflowNodeKind kind) {
    if (source.kind == WorkflowNodeKind.end ||
        kind == WorkflowNodeKind.start ||
        !_nodes.any((node) => node.id == source.id)) {
      return;
    }
    final descriptor = workflowNodeDescriptor(
      kind,
      Theme.of(context).colorScheme,
    );
    final position = _nextNodePosition(source);
    final node = WorkflowNode(
      id: _uuid.v4(),
      kind: kind,
      title: descriptor.label,
      x: position.dx,
      y: position.dy,
      settings: _defaultSettings(kind),
    );
    setState(() {
      _nodes = <WorkflowNode>[..._nodes, node];
      _connections = <WorkflowConnection>[
        ..._connections,
        WorkflowConnection(
          id: _uuid.v4(),
          sourceNodeId: source.id,
          targetNodeId: node.id,
        ),
      ];
      _selectedNodeId = node.id;
      _selectedConnectionId = null;
      _testResult = null;
      _testError = null;
      _testStatus = null;
      _recordHistory('添加${descriptor.label}节点并连接');
    });
    _canvasFocusNode.requestFocus();
  }

  Offset _nextNodePosition(WorkflowNode source) {
    const maxX = _canvasWidth - _nodeWidth - 16;
    const maxY = _canvasHeight - _nodeHeight - 16;
    final x = (source.x + _nodeWidth + 110).clamp(16.0, maxX);
    const verticalStep = _nodeHeight + 42;
    for (var index = 0; index < 20; index++) {
      final level = (index + 1) ~/ 2;
      final direction = index == 0 ? 0 : (index.isOdd ? 1 : -1);
      final y = (source.y + level * verticalStep * direction).clamp(16.0, maxY);
      final candidate = Rect.fromLTWH(x, y, _nodeWidth, _nodeHeight);
      final occupied = _nodes.any(
        (node) => candidate.overlaps(
          Rect.fromLTWH(node.x, node.y, _nodeWidth, _nodeHeight).inflate(24),
        ),
      );
      if (!occupied) return Offset(x, y);
    }
    return Offset(x, (source.y + verticalStep).clamp(16.0, maxY));
  }

  Map<String, Object?> _defaultSettings(WorkflowNodeKind kind) {
    return switch (kind) {
      WorkflowNodeKind.start => <String, Object?>{
        WorkflowSettingKeys.inputFields: <Object?>[],
      },
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
        WorkflowSettingKeys.modelId:
            widget.catalog.models.firstOrNull?.modelId ?? '',
        WorkflowSettingKeys.reasoningEffort:
            widget.catalog.models.firstOrNull?.resolvedReasoningEffort ?? '',
        WorkflowSettingKeys.templateId:
            widget.catalog.templates
                .where((item) => item.id == 'default')
                .firstOrNull
                ?.id ??
            widget.catalog.templates.firstOrNull?.id ??
            '',
        WorkflowSettingKeys.prompt: '',
        WorkflowSettingKeys.inputContent: '',
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
      WorkflowNodeKind.end => <String, Object?>{
        WorkflowSettingKeys.outputFields: <Object?>[],
      },
    };
  }

  void _updateNode(
    WorkflowNode updated, {
    String? historyLabel,
    String? mergeKey,
  }) {
    if (!mounted) return;
    setState(() {
      _nodes = _nodes
          .map((node) => node.id == updated.id ? updated : node)
          .toList(growable: false);
      if (_selectedNodeId == updated.id) {
        _testResult = null;
        _testError = null;
        _testStatus = null;
      }
      _recordHistory(
        historyLabel ?? '修改节点配置',
        mergeKey: mergeKey ?? 'edit:${updated.id}',
      );
    });
  }

  void _deleteSelectedNode() {
    final selectedNode = _selectedNode;
    if (selectedNode == null) return;
    if (selectedNode.kind == WorkflowNodeKind.start && _nodes.length > 1) {
      showOpenHandInfoSnack(context, '请先删除其他节点，再删除开始节点。');
      return;
    }
    final id = selectedNode.id;
    setState(() {
      _nodes = _nodes.where((node) => node.id != id).toList(growable: false);
      _connections = _connections
          .where((edge) => edge.sourceNodeId != id && edge.targetNodeId != id)
          .toList(growable: false);
      _selectedNodeId = null;
      _selectedConnectionId = null;
      _testResult = null;
      _testError = null;
      _testStatus = null;
      _recordHistory('删除${selectedNode.title.trim()}节点');
    });
  }

  void _deleteSelection() {
    if (_selectedNodeId != null) {
      _deleteSelectedNode();
      return;
    }
    final connectionId = _selectedConnectionId;
    if (connectionId == null) return;
    setState(() {
      _connections = _connections
          .where((connection) => connection.id != connectionId)
          .toList(growable: false);
      _selectedConnectionId = null;
      _recordHistory('删除节点连线');
    });
  }

  _WorkflowGraphSnapshot _currentSnapshot() {
    return _WorkflowGraphSnapshot(
      nodes: List<WorkflowNode>.unmodifiable(_nodes),
      connections: List<WorkflowConnection>.unmodifiable(_connections),
    );
  }

  void _recordHistory(String label, {String? mergeKey}) {
    final now = DateTime.now();
    if (_historyIndex + 1 < _history.length) {
      _history.removeRange(_historyIndex + 1, _history.length);
    }
    final entry = _WorkflowHistoryEntry(
      label: label,
      createdAt: now,
      snapshot: _currentSnapshot(),
      mergeKey: mergeKey,
    );
    final previous = _history.last;
    final shouldMerge =
        mergeKey != null &&
        previous.mergeKey == mergeKey &&
        now.difference(previous.createdAt) <= _workflowHistoryMergeWindow;
    if (shouldMerge) {
      _history[_history.length - 1] = entry;
      _historyIndex = _history.length - 1;
      return;
    }
    _history.add(entry);
    if (_history.length > _maxWorkflowHistoryEntries) {
      _history.removeAt(0);
    }
    _historyIndex = _history.length - 1;
  }

  void _undo() {
    if (_canUndo) _restoreHistory(_historyIndex - 1);
  }

  void _redo() {
    if (_canRedo) _restoreHistory(_historyIndex + 1);
  }

  void _restoreHistory(int index) {
    if (index < 0 || index >= _history.length || index == _historyIndex) return;
    final snapshot = _history[index].snapshot;
    setState(() {
      _clearConnectionDragState();
      _historyIndex = index;
      _nodes = List<WorkflowNode>.from(snapshot.nodes);
      _connections = List<WorkflowConnection>.from(snapshot.connections);
      _selectedNodeId = null;
      _selectedConnectionId = null;
      _testResult = null;
      _testError = null;
      _testStatus = null;
    });
    _canvasFocusNode.requestFocus();
  }

  void _selectNode(String nodeId) {
    setState(() {
      _selectedNodeId = nodeId;
      _selectedConnectionId = null;
      _testResult = null;
      _testError = null;
      _testStatus = null;
    });
    _canvasFocusNode.requestFocus();
  }

  void _selectCanvasAt(Offset position) {
    final connectionId = _hitTestConnection(position);
    setState(() {
      _selectedNodeId = null;
      _selectedConnectionId = connectionId;
      _testResult = null;
      _testError = null;
      _testStatus = null;
    });
    _canvasFocusNode.requestFocus();
  }

  String? _hitTestConnection(Offset position) {
    final nodesById = <String, WorkflowNode>{
      for (final node in _nodes) node.id: node,
    };
    final scale = math.max(
      0.35,
      _transformationController.value.getMaxScaleOnAxis(),
    );
    final threshold = 12 / scale;
    final sampleStep = math.max(3.0, 6 / scale);
    for (final connection in _connections.reversed) {
      final source = nodesById[connection.sourceNodeId];
      final target = nodesById[connection.targetNodeId];
      if (source == null || target == null) continue;
      for (final metric in _workflowConnectionPath(
        source,
        target,
      ).computeMetrics()) {
        for (
          var distance = 0.0;
          distance <= metric.length;
          distance += sampleStep
        ) {
          final tangent = metric.getTangentForOffset(distance);
          if (tangent != null &&
              (tangent.position - position).distance <= threshold) {
            return connection.id;
          }
        }
      }
    }
    return null;
  }

  KeyEventResult _handleCanvasKeyEvent(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    final commandPressed = keyboard.isMetaPressed || keyboard.isControlPressed;
    if (commandPressed && event.logicalKey == LogicalKeyboardKey.keyZ) {
      keyboard.isShiftPressed ? _redo() : _undo();
      return KeyEventResult.handled;
    }
    if (commandPressed && event.logicalKey == LogicalKeyboardKey.keyY) {
      _redo();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.delete ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      if (_selectedNodeId == null && _selectedConnectionId == null) {
        return KeyEventResult.ignored;
      }
      _deleteSelection();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape &&
        (_connectingSourceNodeId != null ||
            _selectedNodeId != null ||
            _selectedConnectionId != null)) {
      setState(() {
        _clearConnectionDragState();
        _selectedNodeId = null;
        _selectedConnectionId = null;
      });
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _testSelectedNode() async {
    final node = _selectedNode;
    if (node == null || _testing) return;
    setState(() {
      _testing = true;
      _testResult = null;
      _testError = null;
      _testStatus = null;
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
        variables: _testVariablesFor(node),
      );
      if (!mounted) return;
      setState(() {
        _testResult = _formatExecutionResult(result);
        _testError = null;
        _testStatus = _workflowTestResultStatus(result);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _testResult = null;
        _testError = '$error';
        _testStatus = _workflowTestErrorStatus(error);
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    final name = await showAnimatedDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _WorkflowNameDialog(initialName: _workflowName),
    );
    if (name == null || !mounted) return;
    _workflowName = name;
    final error = _validateNodes();
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

  String? _validateNodes() {
    if (_nodes.isEmpty) return '请至少添加一个节点。';
    for (final node in _nodes) {
      if (node.title.trim().isEmpty) return '节点名称不能为空。';
      if (node.kind == WorkflowNodeKind.start &&
          node.inputFields().isNotEmpty) {
        try {
          WorkflowStructuredOutputParser.validateFields(
            node.inputFields(),
            label: '输入参数',
          );
        } catch (error) {
          return '$error';
        }
      }
      if (node.kind == WorkflowNodeKind.end && node.outputFields().isNotEmpty) {
        try {
          WorkflowStructuredOutputParser.validateFields(node.outputFields());
        } catch (error) {
          return '$error';
        }
      }
      if (node.kind == WorkflowNodeKind.llm) {
        final modelConfigId = node
            .stringSetting(WorkflowSettingKeys.modelConfigId)
            .trim();
        final provider = widget.catalog.models
            .where((item) => item.id == modelConfigId)
            .firstOrNull;
        if (provider == null) {
          return '请为 LLM 节点选择模型。';
        }
        final storedModelId = node
            .stringSetting(WorkflowSettingKeys.modelId)
            .trim();
        final modelId = storedModelId.isEmpty
            ? provider.modelId
            : storedModelId;
        if (modelId.isEmpty || !provider.allModelIds.contains(modelId)) {
          return 'LLM 节点所选模型已不可用，请重新选择。';
        }
        final reasoningEffort = node
            .stringSetting(WorkflowSettingKeys.reasoningEffort)
            .trim();
        if (reasoningEffort.isNotEmpty) {
          final model = provider.copyWith(modelId: modelId);
          final supported =
              model.resolvedReasoningEffortControlEnabled &&
              model.resolvedReasoningEffortOptions.any(
                (option) =>
                    option.isSelectable &&
                    option.value.toLowerCase() == reasoningEffort.toLowerCase(),
              );
          if (!supported) return 'LLM 节点的推理强度已不可用，请重新选择。';
        }
        if (node.stringSetting(WorkflowSettingKeys.prompt).trim().isEmpty) {
          return '请填写 LLM 节点提示词。';
        }
      }
      if (node.kind == WorkflowNodeKind.httpRequest &&
          node.stringSetting(WorkflowSettingKeys.url).trim().isEmpty) {
        return '请填写 HTTP 节点请求 URL。';
      }
      if (node.kind == WorkflowNodeKind.httpRequest) {
        final headersError = validateWorkflowKeyValueEntries(
          node.keyValueSetting(WorkflowSettingKeys.headers),
          label: '请求头',
          httpHeaders: true,
        );
        if (headersError != null) return headersError;
        final queryError = validateWorkflowKeyValueEntries(
          node.keyValueSetting(WorkflowSettingKeys.queryParameters),
          label: '请求参数',
        );
        if (queryError != null) return queryError;
        final bodyFormat = WorkflowHttpBodyFormat.fromStorage(
          node.stringSetting(WorkflowSettingKeys.bodyFormat),
        );
        if (bodyFormat.usesFields) {
          final bodyError = validateWorkflowKeyValueEntries(
            node.keyValueSetting(WorkflowSettingKeys.bodyEntries),
            label: '请求体字段',
          );
          if (bodyError != null) return bodyError;
        }
      }
      if (node.boolSetting(WorkflowSettingKeys.structuredOutput)) {
        try {
          WorkflowStructuredOutputParser.validateFields(node.outputFields());
        } catch (error) {
          return '$error';
        }
      }
    }
    return validateWorkflowParameterNames(_nodes);
  }

  List<WorkflowParameterReference> _availableReferencesFor(
    WorkflowNode target,
  ) {
    if (target.kind == WorkflowNodeKind.start) {
      return const <WorkflowParameterReference>[];
    }
    final upstreamIds = <String>{};
    final pending = <String>[target.id];
    while (pending.isNotEmpty) {
      final targetId = pending.removeLast();
      for (final connection in _connections) {
        if (connection.targetNodeId != targetId ||
            connection.sourceNodeId == target.id ||
            !upstreamIds.add(connection.sourceNodeId)) {
          continue;
        }
        pending.add(connection.sourceNodeId);
      }
    }

    final names = <String>{};
    return _nodes
        .where((node) => upstreamIds.contains(node.id))
        .expand(
          (node) => node
              .declaredParameterFields()
              .where((field) {
                final name = field.name.trim();
                return workflowParameterNamePattern.hasMatch(name) &&
                    names.add(name);
              })
              .map(
                (field) => WorkflowParameterReference(
                  nodeId: node.id,
                  nodeTitle: node.title.trim().isEmpty ? '未命名节点' : node.title,
                  field: field,
                ),
              ),
        )
        .toList(growable: false);
  }

  Map<String, String> _reservedParameterNamesFor(WorkflowNode current) {
    return <String, String>{
      for (final node in _nodes)
        if (node.id != current.id)
          for (final field in node.declaredParameterFields())
            if (field.name.trim().isNotEmpty)
              field.name.trim(): node.title.trim().isEmpty
                  ? '未命名节点'
                  : node.title,
    };
  }

  Map<String, Object?> _testVariablesFor(WorkflowNode node) {
    final values = <String, Object?>{
      'input': '测试输入',
      'status': 'success',
      'value': 'demo',
      'items': <Object?>['第一项', '第二项'],
    };
    for (final reference in _availableReferencesFor(node)) {
      values.putIfAbsent(
        reference.name,
        () => switch (reference.field.type) {
          WorkflowOutputType.string => '测试值',
          WorkflowOutputType.integer => 1,
          WorkflowOutputType.number => 1.5,
          WorkflowOutputType.boolean => true,
          WorkflowOutputType.object => <String, Object?>{'key': 'value'},
          WorkflowOutputType.array => <Object?>['第一项', '第二项'],
        },
      );
    }
    return values;
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

class _CanvasEmptyState extends StatelessWidget {
  const _CanvasEmptyState({required this.onAddStart});

  final VoidCallback onAddStart;

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
            '工作流必须从开始节点进入。添加后可继续配置处理节点与结束节点。',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          kOpenHandGap16,
          FilledButton.icon(
            onPressed: onAddStart,
            style: FilledButton.styleFrom(shape: _workflowButtonShape),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('添加开始节点'),
          ),
        ],
      ),
    );
  }
}

class _CanvasToolbar extends StatelessWidget {
  const _CanvasToolbar({
    required this.scale,
    required this.canDelete,
    required this.canUndo,
    required this.canRedo,
    required this.history,
    required this.historyIndex,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onReset,
    required this.onDelete,
    required this.onUndo,
    required this.onRedo,
    required this.onHistorySelected,
  });

  final double scale;
  final bool canDelete;
  final bool canUndo;
  final bool canRedo;
  final List<_WorkflowHistoryEntry> history;
  final int historyIndex;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onReset;
  final VoidCallback onDelete;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final ValueChanged<int> onHistorySelected;

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
              tooltip: '删除所选节点或连线',
              icon: Icons.delete_outline_rounded,
              onPressed: canDelete ? onDelete : null,
            ),
            Container(
              width: 1,
              height: 24,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              color: theme.colorScheme.outlineVariant,
            ),
            _ToolbarButton(
              tooltip: '撤销（⌘/Ctrl+Z）',
              icon: Icons.undo_rounded,
              onPressed: canUndo ? onUndo : null,
            ),
            _ToolbarButton(
              tooltip: '重做（⌘/Ctrl+Shift+Z 或 Ctrl+Y）',
              icon: Icons.redo_rounded,
              onPressed: canRedo ? onRedo : null,
            ),
            Container(
              width: 1,
              height: 24,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              color: theme.colorScheme.outlineVariant,
            ),
            AnimatedPopupMenuButton<int>(
              tooltip: '变更历史',
              icon: const Icon(Icons.history_rounded, size: 19),
              padding: EdgeInsets.zero,
              style: IconButton.styleFrom(
                backgroundColor: Colors.transparent,
                fixedSize: const Size.square(36),
                padding: EdgeInsets.zero,
                shape: _workflowButtonShape,
              ),
              constraints: const BoxConstraints(
                minWidth: 300,
                maxWidth: 340,
                maxHeight: 480,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(kOpenHandRadius14),
              ),
              onSelected: onHistorySelected,
              itemBuilder: (_) => history
                  .asMap()
                  .entries
                  .toList(growable: false)
                  .reversed
                  .map(
                    (entry) => PopupMenuItem<int>(
                      value: entry.key,
                      height: 58,
                      child: _HistoryMenuItem(
                        entry: entry.value,
                        current: entry.key == historyIndex,
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryMenuItem extends StatelessWidget {
  const _HistoryMenuItem({required this.entry, required this.current});

  final _WorkflowHistoryEntry entry;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 270,
      child: Row(
        children: [
          Icon(
            current ? Icons.check_circle_rounded : Icons.history_rounded,
            size: 20,
            color: current
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
          kOpenHandHGap10,
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: current ? theme.colorScheme.primary : null,
                    fontWeight: current ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
                kOpenHandGap2,
                Text(
                  _historyTimeText(entry.createdAt),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
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

String _historyTimeText(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}

class _WorkflowNameDialog extends StatefulWidget {
  const _WorkflowNameDialog({required this.initialName});

  final String initialName;

  @override
  State<_WorkflowNameDialog> createState() => _WorkflowNameDialogState();
}

class _WorkflowNameDialogState extends State<_WorkflowNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
  );
  final FocusNode _focusNode = FocusNode();

  bool get _canSave => _controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
        _controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _controller.text.length,
        );
      }
    });
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_handleChanged)
      ..dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleChanged() => setState(() {});

  void _confirm() {
    final name = _controller.text.trim();
    if (name.isNotEmpty) Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return buildOpenHandDialog(
      maxWidth: 500,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(kOpenHandRadius12),
                  ),
                  child: Icon(
                    Icons.edit_note_rounded,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                kOpenHandHGap12,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '为工作流命名',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      kOpenHandGap2,
                      Text(
                        '输入一个清晰、便于识别的名称。',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            kOpenHandGap20,
            TextField(
              controller: _controller,
              focusNode: _focusNode,
              maxLength: 80,
              buildCounter: openHandHiddenTextFieldCounter,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                if (_canSave) _confirm();
              },
              decoration: InputDecoration(
                labelText: '工作流名称',
                hintText: '例如：内容审核与发布',
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerLow,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(kOpenHandRadius14),
                ),
              ),
            ),
            kOpenHandGap18,
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OpenHandDialogActionButton.secondary(
                  label: '取消',
                  onPressed: () => Navigator.of(context).pop(),
                  shape: _workflowButtonShape,
                ),
                kOpenHandHGap12,
                OpenHandDialogActionButton.primary(
                  label: '确认保存',
                  onPressed: _canSave ? _confirm : null,
                  icon: Icons.save_rounded,
                  shape: _workflowButtonShape,
                ),
              ],
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
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 19),
        style: IconButton.styleFrom(
          backgroundColor: Colors.transparent,
          fixedSize: const Size.square(36),
          padding: EdgeInsets.zero,
          shape: _workflowButtonShape,
        ),
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
    required this.selectedConnectionId,
    required this.draftSourceNodeId,
    required this.draftTargetNodeId,
    required this.draftEnd,
    required this.draftValid,
    required this.color,
    required this.errorColor,
    required this.mutedColor,
  });

  final List<WorkflowNode> nodes;
  final List<WorkflowConnection> connections;
  final String? selectedConnectionId;
  final String? draftSourceNodeId;
  final String? draftTargetNodeId;
  final Offset? draftEnd;
  final bool draftValid;
  final Color color;
  final Color errorColor;
  final Color mutedColor;

  @override
  void paint(Canvas canvas, Size size) {
    final byId = <String, WorkflowNode>{
      for (final node in nodes) node.id: node,
    };
    for (final edge in connections) {
      final source = byId[edge.sourceNodeId];
      final target = byId[edge.targetNodeId];
      if (source == null || target == null) continue;
      final selected = edge.id == selectedConnectionId;
      final linePaint = Paint()
        ..color = color.withValues(alpha: selected ? 1 : 0.72)
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 4 : 2.4
        ..strokeCap = StrokeCap.round;
      final haloPaint = Paint()
        ..color = (selected ? color : mutedColor).withValues(
          alpha: selected ? 0.2 : 0.16,
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 12 : 7;
      final start = Offset(source.x + _nodeWidth, source.y + _nodeHeight / 2);
      final end = Offset(target.x, target.y + _nodeHeight / 2);
      final distance = math.max(70, (end.dx - start.dx).abs() * 0.46);
      final path = _workflowConnectionPath(source, target);
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

    final draftSource = byId[draftSourceNodeId];
    final pointerEnd = draftEnd;
    if (draftSource == null || pointerEnd == null) return;
    final draftTarget = byId[draftTargetNodeId];
    final start = Offset(
      draftSource.x + _nodeWidth,
      draftSource.y + _nodeHeight / 2,
    );
    final end = draftTarget == null
        ? pointerEnd
        : Offset(draftTarget.x, draftTarget.y + _nodeHeight / 2);
    final invalidTarget = draftTarget != null && !draftValid;
    final draftColor = invalidTarget ? errorColor : color;
    final path = _workflowConnectionPathBetween(start, end);
    canvas.drawPath(
      path,
      Paint()
        ..color = draftColor.withValues(alpha: 0.16)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = draftColor.withValues(alpha: 0.92)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      end,
      draftTarget == null ? 4 : 5,
      Paint()..color = draftColor,
    );
  }

  @override
  bool shouldRepaint(_WorkflowConnectionPainter oldDelegate) {
    return nodes != oldDelegate.nodes ||
        connections != oldDelegate.connections ||
        selectedConnectionId != oldDelegate.selectedConnectionId ||
        draftSourceNodeId != oldDelegate.draftSourceNodeId ||
        draftTargetNodeId != oldDelegate.draftTargetNodeId ||
        draftEnd != oldDelegate.draftEnd ||
        draftValid != oldDelegate.draftValid ||
        color != oldDelegate.color ||
        errorColor != oldDelegate.errorColor ||
        mutedColor != oldDelegate.mutedColor;
  }
}

Path _workflowConnectionPath(WorkflowNode source, WorkflowNode target) {
  final start = Offset(source.x + _nodeWidth, source.y + _nodeHeight / 2);
  final end = Offset(target.x, target.y + _nodeHeight / 2);
  return _workflowConnectionPathBetween(start, end);
}

Path _workflowConnectionPathBetween(Offset start, Offset end) {
  final distance = math.max(70, (end.dx - start.dx).abs() * 0.46);
  return Path()
    ..moveTo(start.dx, start.dy)
    ..cubicTo(
      start.dx + distance,
      start.dy,
      end.dx - distance,
      end.dy,
      end.dx,
      end.dy,
    );
}

String _nodeSummary(WorkflowNode node) {
  return switch (node.kind) {
    WorkflowNodeKind.start =>
      node.inputFields().isEmpty
          ? '暂无输入参数'
          : '${node.inputFields().length} 个输入参数',
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
    WorkflowNodeKind.end =>
      node.outputFields().isEmpty
          ? '暂无输出参数'
          : '${node.outputFields().length} 个输出参数',
  };
}

String _formatExecutionResult(WorkflowNodeExecutionResult result) {
  final output = result.output;
  final formatted = output is String
      ? output
      : const JsonEncoder.withIndent('  ').convert(output);
  return '尝试 ${result.attempts} 次 · ${result.duration.inMilliseconds} 毫秒\n\n$formatted';
}

WorkflowNodeTestStatus _workflowTestResultStatus(
  WorkflowNodeExecutionResult result,
) {
  final output = result.output;
  final statusCode = output is Map ? output['status_code'] : null;
  if (result.attempts > 1 || statusCode == 206 || statusCode == 207) {
    return WorkflowNodeTestStatus.warning;
  }
  return WorkflowNodeTestStatus.success;
}

WorkflowNodeTestStatus _workflowTestErrorStatus(Object error) {
  Object? current = error;
  for (var depth = 0; depth < 6 && current != null; depth++) {
    if (current is TimeoutException) return WorkflowNodeTestStatus.warning;
    current = current is WorkflowNodeExecutionException ? current.cause : null;
  }
  final message = '$error'.toLowerCase();
  if (message.contains('超时') ||
      message.contains('timeout') ||
      message.contains('部分成功') ||
      message.contains('partial')) {
    return WorkflowNodeTestStatus.warning;
  }
  return WorkflowNodeTestStatus.failure;
}

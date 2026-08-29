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
const double _conditionBranchStart = 70;
const double _conditionBranchSpacing = 28;
const double _containerMinWidth = 360;
const double _containerMinHeight = 196;
const double _containerHeaderHeight = 66;
const double _containerChildLeft = 132;
const double _containerChildTop = 96;
const double _containerStartNodeSize = 44;
const double _containerPadding = 34;
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
    dismissOnEscape: false,
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
  late final AiTtsPlaybackService _ttsPlaybackService = AiTtsPlaybackService();
  late final AiTranslationService _translationService = AiTranslationService();
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
  late List<WorkflowNode> _nodes;
  late List<WorkflowConnection> _connections = List<WorkflowConnection>.from(
    widget.workflow?.connections ?? const <WorkflowConnection>[],
  );
  String? _selectedNodeId;
  String? _selectedConnectionId;
  bool _testing = false;
  String? _testResult;
  String? _testError;
  WorkflowNodeTestStatus? _testStatus;
  final Map<String, WorkflowLlmConversation> _llmConversations =
      <String, WorkflowLlmConversation>{};
  String? _conversationNodeId;
  String? _connectingSourceNodeId;
  String? _connectingSourceHandleId;
  String? _connectionTargetNodeId;
  String? _connectionTargetError;
  Offset? _connectionDragPosition;
  late final List<_WorkflowHistoryEntry> _history;
  late final String _initialDraftFingerprint;
  int _historyIndex = 0;
  bool _closeConfirmationOpen = false;
  bool _allowPop = false;

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
  bool get _hasUnsavedChanges =>
      _currentDraftFingerprint() != _initialDraftFingerprint;

  @override
  void initState() {
    super.initState();
    _nodes = _fitContainerSizes(
      List<WorkflowNode>.from(widget.workflow?.nodes ?? const <WorkflowNode>[]),
    );
    _initialDraftFingerprint = _currentDraftFingerprint();
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
    unawaited(_ttsPlaybackService.dispose());
    _translationService.dispose();
    _transformationController.dispose();
    _canvasFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = Material(
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
                                nestedOutputReferences:
                                    _nestedOutputReferencesFor(_selectedNode!),
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
                                conversation:
                                    _llmConversations[_selectedNode!.id],
                                showConversation:
                                    _conversationNodeId == _selectedNode!.id,
                                onConversationModeChanged: (show) {
                                  setState(() {
                                    _conversationNodeId = show
                                        ? _selectedNode!.id
                                        : null;
                                  });
                                },
                                ttsPlaybackService: _ttsPlaybackService,
                                translationService: _translationService,
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
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_requestClose());
      },
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              unawaited(_requestClose()),
        },
        child: content,
      ),
    );
  }

  String _currentDraftFingerprint() => jsonEncode(<String, Object?>{
    'name': _workflowName,
    'nodes': _nodes.map((node) => node.toJson()).toList(growable: false),
    'connections': _connections
        .map((connection) => connection.toJson())
        .toList(growable: false),
  });

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
            onPressed: _closeConfirmationOpen ? null : _requestClose,
            style: actionStyle,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  Future<void> _requestClose() async {
    if (!_hasUnsavedChanges) {
      _popEditor();
      return;
    }
    if (_closeConfirmationOpen) return;
    setState(() => _closeConfirmationOpen = true);
    final discard = await showOpenHandConfirmDialog(
      context: context,
      title: '放弃未保存的工作流？',
      message: '当前工作流存在未保存的变更。关闭后，这些内容将无法恢复。',
      cancelLabel: '继续编辑',
      confirmLabel: '放弃并关闭',
      icon: Icon(
        Icons.warning_amber_rounded,
        color: Theme.of(context).colorScheme.error,
      ),
      destructive: true,
      barrierDismissible: false,
    );
    if (!mounted) return;
    setState(() => _closeConfirmationOpen = false);
    if (discard) _popEditor();
  }

  void _popEditor([WorkflowDefinition? result]) {
    if (!mounted || _allowPop) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(result);
    });
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
                            scopeParentId: null,
                            canvasOrigin: Offset.zero,
                            selectedConnectionId: _selectedConnectionId,
                            draftSourceNodeId: _connectingSourceNodeId,
                            draftSourceHandleId: _connectingSourceHandleId,
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
                    for (final node in _nodes.where((item) => item.isContainer))
                      _buildNodeCard(context, node),
                    for (final node in _nodes.where(
                      (item) => !item.isContainer,
                    ))
                      _buildNodeCard(context, node),
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
    if (node.isContainer) return _buildContainerNodeCard(context, node);
    final selected = node.id == _selectedNodeId;
    final connectionTarget = node.id == _connectionTargetNodeId;
    final connectionTargetValid =
        connectionTarget && _connectionTargetError == null;
    final theme = Theme.of(context);
    final descriptor = workflowNodeDescriptor(node.kind, theme.colorScheme);
    final nodeHeight = _nodeHeightFor(node);
    final controlFlowNode = const <WorkflowNodeKind>{
      WorkflowNodeKind.condition,
      WorkflowNodeKind.loop,
      WorkflowNodeKind.iteration,
      WorkflowNodeKind.loopExit,
    }.contains(node.kind);
    final idleColor = controlFlowNode
        ? Color.alphaBlend(
            descriptor.color.withValues(alpha: 0.07),
            theme.colorScheme.surfaceContainerHigh,
          )
        : theme.colorScheme.surfaceContainerHigh;
    return Positioned(
      left: node.x,
      top: node.y,
      width: _nodeWidth + _nodeAddButtonHitSize / 2,
      height: nodeHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 0,
            width: _nodeWidth,
            height: nodeHeight,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _selectNode(node.id),
              onPanUpdate: (details) => _moveNode(node, details.delta),
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
                        : idleColor,
                    borderRadius: BorderRadius.circular(kOpenHandRadius18),
                    border: Border.all(
                      color: connectionTarget
                          ? (connectionTargetValid
                                ? theme.colorScheme.primary
                                : theme.colorScheme.error)
                          : selected
                          ? descriptor.color
                          : controlFlowNode
                          ? descriptor.color.withValues(alpha: 0.42)
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
                  child: _buildNodeCardContent(context, node, descriptor),
                ),
              ),
            ),
          ),
          if (node.kind != WorkflowNodeKind.start)
            Positioned(
              left: -5,
              top: nodeHeight / 2 - 5,
              child: AnimatedContainer(
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
                  border: Border.all(
                    color: theme.colorScheme.surface,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          if (node.kind == WorkflowNodeKind.condition)
            for (final branch in _conditionBranches(node).indexed)
              Positioned(
                left: _nodeWidth - _nodeAddButtonHitSize / 2,
                top:
                    _conditionBranchStart +
                    branch.$1 * _conditionBranchSpacing -
                    _nodeAddButtonHitSize / 2,
                child: _buildAddNodeButton(
                  context,
                  node,
                  sourceHandleId: branch.$2.id,
                  tooltip: '从 ${branch.$2.label} 分支添加或连接节点',
                ),
              )
          else if (!isWorkflowTerminalNodeKind(node.kind))
            Positioned(
              left: _nodeWidth - _nodeAddButtonHitSize / 2,
              top: (nodeHeight - _nodeAddButtonHitSize) / 2,
              child: _buildAddNodeButton(context, node),
            ),
        ],
      ),
    );
  }

  Widget _buildContainerNodeCard(BuildContext context, WorkflowNode node) {
    final theme = Theme.of(context);
    final descriptor = workflowNodeDescriptor(node.kind, theme.colorScheme);
    final selected = node.id == _selectedNodeId;
    final connectionTarget = node.id == _connectionTargetNodeId;
    final connectionTargetValid =
        connectionTarget && _connectionTargetError == null;
    final width = _nodeWidthFor(node);
    final height = _nodeHeightFor(node);
    final childCount = _nodes
        .where((item) => item.parentNodeId == node.id)
        .length;
    final borderColor = connectionTarget
        ? connectionTargetValid
              ? theme.colorScheme.primary
              : theme.colorScheme.error
        : selected
        ? descriptor.color
        : descriptor.color.withValues(alpha: 0.5);
    return Positioned(
      left: node.x,
      top: node.y,
      child: TweenAnimationBuilder<Offset>(
        tween: Tween<Offset>(
          begin: Offset(width, height),
          end: Offset(width, height),
        ),
        duration: openHandMotionDuration(context, kOpenHandMotion260),
        curve: Curves.easeOutBack,
        builder: (context, size, _) {
          final animatedWidth = size.dx;
          final animatedHeight = size.dy;
          final startCenterY = _containerStartCenterY(
            containerHeight: animatedHeight,
            hasChildren: childCount > 0,
          );
          return SizedBox(
            width: animatedWidth + _nodeAddButtonHitSize / 2,
            height: animatedHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  width: animatedWidth,
                  height: animatedHeight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (details) {
                      final position =
                          details.localPosition + Offset(node.x, node.y);
                      final connectionId = _hitTestConnection(position);
                      connectionId == null
                          ? _selectNode(node.id)
                          : _selectConnection(connectionId);
                    },
                    onPanUpdate: (details) => _moveNode(node, details.delta),
                    child: AnimatedContainer(
                      duration: openHandMotionDuration(
                        context,
                        kOpenHandMotion180,
                      ),
                      curve: Curves.easeOutCubic,
                      decoration: BoxDecoration(
                        color: Color.alphaBlend(
                          descriptor.color.withValues(alpha: 0.055),
                          theme.colorScheme.surfaceContainerLow,
                        ),
                        borderRadius: BorderRadius.circular(kOpenHandRadius20),
                        boxShadow: selected || connectionTarget
                            ? <BoxShadow>[
                                BoxShadow(
                                  color: borderColor.withValues(alpha: 0.16),
                                  blurRadius: 22,
                                  offset: const Offset(0, 7),
                                ),
                              ]
                            : const <BoxShadow>[],
                      ),
                      foregroundDecoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(kOpenHandRadius20),
                        border: Border.all(
                          color: borderColor,
                          width: selected || connectionTarget ? 2 : 1.2,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            top: _containerHeaderHeight,
                            child: ColoredBox(
                              color: theme.colorScheme.surfaceContainerLowest
                                  .withValues(alpha: 0.7),
                              child: CustomPaint(
                                painter: _WorkflowConnectionPainter(
                                  nodes: _nodes,
                                  connections: _connections,
                                  scopeParentId: node.id,
                                  canvasOrigin: Offset(
                                    node.x,
                                    node.y + _containerHeaderHeight,
                                  ),
                                  selectedConnectionId: _selectedConnectionId,
                                  draftSourceNodeId: _connectingSourceNodeId,
                                  draftSourceHandleId:
                                      _connectingSourceHandleId,
                                  draftTargetNodeId: _connectionTargetNodeId,
                                  draftEnd: _connectionDragPosition,
                                  draftValid:
                                      _connectionTargetNodeId != null &&
                                      _connectionTargetError == null,
                                  color: descriptor.color,
                                  errorColor: theme.colorScheme.error,
                                  mutedColor: theme.colorScheme.outline,
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                            child: Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: descriptor.color.withValues(
                                      alpha: 0.15,
                                    ),
                                    borderRadius: BorderRadius.circular(
                                      kOpenHandRadius10,
                                    ),
                                  ),
                                  child: Icon(
                                    descriptor.icon,
                                    color: descriptor.color,
                                    size: 20,
                                  ),
                                ),
                                kOpenHandHGap10,
                                Expanded(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        node.title.trim().isEmpty
                                            ? descriptor.label
                                            : node.title.trim(),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w900,
                                            ),
                                      ),
                                      Text(
                                        '$childCount 个内部节点 · ${_nodeSummary(node)}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.drag_indicator_rounded,
                                  size: 18,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ],
                            ),
                          ),
                          Positioned(
                            left: 28,
                            top: startCenterY - _containerStartNodeSize / 2,
                            child: Container(
                              width: _containerStartNodeSize,
                              height: _containerStartNodeSize,
                              decoration: BoxDecoration(
                                color: descriptor.color.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(
                                  kOpenHandRadius14,
                                ),
                                border: Border.all(
                                  color: descriptor.color.withValues(
                                    alpha: 0.5,
                                  ),
                                ),
                              ),
                              child: Icon(
                                Icons.home_rounded,
                                size: 20,
                                color: descriptor.color,
                              ),
                            ),
                          ),
                          Positioned(
                            left: 76,
                            top: startCenterY - _nodeAddButtonHitSize / 2,
                            child: _buildAddNodeButton(
                              context,
                              node,
                              sourceHandleId: workflowContainerStartHandleId,
                              tooltip: '添加内部工作流的第一个节点',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: -5,
                  top: _containerHeaderHeight / 2 - 5,
                  child: _buildInputPort(
                    context,
                    connectionTarget: connectionTarget,
                    connectionTargetValid: connectionTargetValid,
                  ),
                ),
                Positioned(
                  left: animatedWidth - _nodeAddButtonHitSize / 2,
                  top: (_containerHeaderHeight - _nodeAddButtonHitSize) / 2,
                  child: _buildAddNodeButton(
                    context,
                    node,
                    tooltip: '添加或连接循环结束后的节点',
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildInputPort(
    BuildContext context, {
    required bool connectionTarget,
    required bool connectionTargetValid,
  }) {
    final theme = Theme.of(context);
    return AnimatedContainer(
      duration: openHandMotionDuration(context, kOpenHandMotion180),
      width: connectionTarget ? 10 : 8,
      height: connectionTarget ? 10 : 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: connectionTarget
            ? connectionTargetValid
                  ? theme.colorScheme.primary
                  : theme.colorScheme.error
            : theme.colorScheme.outline,
        border: Border.all(color: theme.colorScheme.surface, width: 1.5),
      ),
    );
  }

  Widget _buildNodeCardContent(
    BuildContext context,
    WorkflowNode node,
    ({String label, String description, IconData icon, Color color}) descriptor,
  ) {
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
        if (node.kind == WorkflowNodeKind.condition) ...[
          kOpenHandGap8,
          ..._conditionBranches(node).map(
            (branch) => SizedBox(
              height: _conditionBranchSpacing,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      branch.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: descriptor.color,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ] else ...[
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
        ],
        if (node.kind != WorkflowNodeKind.condition)
          Row(
            children: [
              const Spacer(),
              Text(
                descriptor.label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: descriptor.color,
                  fontWeight: FontWeight.w800,
                ),
              ),
              kOpenHandHGap6,
              if (!isWorkflowTerminalNodeKind(node.kind))
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

  Widget _buildAddNodeButton(
    BuildContext context,
    WorkflowNode source, {
    String? sourceHandleId,
    String tooltip = '单击添加节点，拖拽连接已有节点',
  }) {
    final theme = Theme.of(context);
    final connecting =
        source.id == _connectingSourceNodeId &&
        sourceHandleId == _connectingSourceHandleId;
    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: connecting
            ? SystemMouseCursors.grabbing
            : SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (details) => _startConnectionDrag(
            source,
            details.globalPosition,
            sourceHandleId: sourceHandleId,
          ),
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
                        onTap: () => _showAddNodeMenu(
                          buttonContext,
                          source,
                          sourceHandleId: sourceHandleId,
                        ),
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
    WorkflowNode source, {
    String? sourceHandleId,
  }) async {
    final theme = Theme.of(buttonContext);
    final nestedScope = _connectionScopeForSource(source, sourceHandleId);
    final nestedParent = nestedScope == null
        ? null
        : _nodes.where((node) => node.id == nestedScope).firstOrNull;
    final selected = await showAnimatedAnchoredPopupMenu<WorkflowNodeKind>(
      context: buttonContext,
      offset: const Offset(18, 0),
      constraints: const BoxConstraints(minWidth: 260, maxWidth: 300),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kOpenHandRadius14),
      ),
      items: WorkflowNodeKind.values
          .where(
            (kind) => nestedScope == null
                ? kind != WorkflowNodeKind.start &&
                      kind != WorkflowNodeKind.loopExit
                : kind == WorkflowNodeKind.condition ||
                      kind == WorkflowNodeKind.llm ||
                      kind == WorkflowNodeKind.httpRequest ||
                      kind == WorkflowNodeKind.parameterAssignment ||
                      kind == WorkflowNodeKind.listOperation ||
                      kind == WorkflowNodeKind.loopExit &&
                          nestedParent?.kind == WorkflowNodeKind.loop,
          )
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
    if (latestSource != null) {
      _addConnectedNode(latestSource, selected, sourceHandleId: sourceHandleId);
    }
  }

  void _startConnectionDrag(
    WorkflowNode source,
    Offset globalPosition, {
    String? sourceHandleId,
  }) {
    if (isWorkflowTerminalNodeKind(source.kind) ||
        !_nodes.any((node) => node.id == source.id)) {
      return;
    }
    final position = _canvasPosition(globalPosition);
    if (position == null) return;
    setState(() {
      _connectingSourceNodeId = source.id;
      _connectingSourceHandleId = sourceHandleId;
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
    final source = _nodes.where((node) => node.id == sourceId).firstOrNull;
    final target = source == null
        ? null
        : _nodeAtPosition(
            position,
            source: source,
            sourceHandleId: _connectingSourceHandleId,
          );
    setState(() {
      _connectionDragPosition = position;
      _connectionTargetNodeId = target?.id;
      _connectionTargetError = source == null || target == null
          ? null
          : _connectionError(
              source,
              target,
              sourceHandleId: _connectingSourceHandleId,
            );
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
        : _connectionError(
            source,
            target,
            sourceHandleId: _connectingSourceHandleId,
          );
    if (source == null || target == null || error != null) {
      _cancelConnectionDrag();
      if (error != null && mounted) showOpenHandInfoSnack(context, error);
      return;
    }

    final connection = WorkflowConnection(
      id: _uuid.v4(),
      sourceNodeId: source.id,
      targetNodeId: target.id,
      sourceHandleId: _connectingSourceHandleId,
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
    _connectingSourceHandleId = null;
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
    required WorkflowNode source,
    required String? sourceHandleId,
  }) {
    final sourceScope = _connectionScopeForSource(source, sourceHandleId);
    final candidates = <WorkflowNode>[
      ..._nodes.reversed.where((node) => !node.isContainer),
      ..._nodes.reversed.where((node) => node.isContainer),
    ];
    for (final node in candidates) {
      if (node.id == source.id || node.parentNodeId != sourceScope) continue;
      final bounds = Rect.fromLTWH(
        node.x,
        node.y,
        _nodeWidthFor(node),
        _nodeHeightFor(node),
      ).inflate(8);
      if (bounds.contains(position)) return node;
    }
    return null;
  }

  String? _connectionError(
    WorkflowNode source,
    WorkflowNode target, {
    String? sourceHandleId,
  }) {
    if (source.id == target.id) return '节点不能连接到自身。';
    if (isWorkflowTerminalNodeKind(source.kind)) {
      return source.kind == WorkflowNodeKind.loopExit
          ? '退出循环节点不能连接后续内部节点。'
          : '结束节点不能连接后续节点。';
    }
    final sourceScope = _connectionScopeForSource(source, sourceHandleId);
    if (target.parentNodeId != sourceScope) return '节点只能连接到同一工作流作用域。';
    if (sourceHandleId == workflowContainerStartHandleId &&
        (!source.isContainer || target.parentNodeId != source.id)) {
      return '内部起点只能连接当前容器内的节点。';
    }
    if (source.kind == WorkflowNodeKind.condition &&
        !_conditionBranches(
          source,
        ).any((branch) => branch.id == sourceHandleId)) {
      return '请从条件节点的具体分支发起连接。';
    }
    if (target.kind == WorkflowNodeKind.start) return '开始节点不能作为后续节点。';
    if (_connections.any(
      (connection) =>
          connection.sourceNodeId == source.id &&
          connection.targetNodeId == target.id &&
          connection.sourceHandleId == sourceHandleId,
    )) {
      return '这两个节点已经连接。';
    }
    if (_wouldCreateConnectionCycle(source.id, target.id)) {
      return '该连接会形成循环，请调整节点方向。';
    }
    return null;
  }

  String? _connectionScopeForSource(
    WorkflowNode source,
    String? sourceHandleId,
  ) {
    if (source.isContainer &&
        sourceHandleId == workflowContainerStartHandleId) {
      return source.id;
    }
    return source.parentNodeId;
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
    if (kind == WorkflowNodeKind.loopExit) {
      showOpenHandInfoSnack(context, '退出循环节点只能添加到循环节点内部。');
      return;
    }
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

  void _addConnectedNode(
    WorkflowNode source,
    WorkflowNodeKind kind, {
    String? sourceHandleId,
  }) {
    final parentNodeId = _connectionScopeForSource(source, sourceHandleId);
    final parent = parentNodeId == null
        ? null
        : _nodes.where((node) => node.id == parentNodeId).firstOrNull;
    if (isWorkflowTerminalNodeKind(source.kind) ||
        kind == WorkflowNodeKind.start ||
        (kind == WorkflowNodeKind.loopExit &&
            (parentNodeId == null || parent?.kind != WorkflowNodeKind.loop)) ||
        (parentNodeId != null &&
            (kind == WorkflowNodeKind.end || isWorkflowContainerKind(kind))) ||
        !_nodes.any((node) => node.id == source.id)) {
      return;
    }
    final descriptor = workflowNodeDescriptor(
      kind,
      Theme.of(context).colorScheme,
    );
    final position = parentNodeId == null
        ? _nextNodePosition(source, kind)
        : _nextNestedNodePosition(source, parentNodeId, kind);
    final node = WorkflowNode(
      id: _uuid.v4(),
      kind: kind,
      title: descriptor.label,
      x: position.dx,
      y: position.dy,
      parentNodeId: parentNodeId,
      settings: _defaultSettings(kind),
    );
    setState(() {
      _nodes = _fitContainerSizes(<WorkflowNode>[..._nodes, node]);
      _connections = <WorkflowConnection>[
        ..._connections,
        WorkflowConnection(
          id: _uuid.v4(),
          sourceNodeId: source.id,
          targetNodeId: node.id,
          sourceHandleId: sourceHandleId,
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

  Offset _nextNestedNodePosition(
    WorkflowNode source,
    String parentNodeId,
    WorkflowNodeKind targetKind,
  ) {
    final parent = _nodes.where((node) => node.id == parentNodeId).firstOrNull;
    if (parent == null) return Offset(source.x, source.y);
    final targetHeight = targetKind == WorkflowNodeKind.condition
        ? _conditionBranchStart + _conditionBranchSpacing + 32
        : _nodeHeight;
    final fromStart = source.id == parent.id;
    const maxX = _canvasWidth - _nodeWidth - _containerPadding;
    final maxY = _canvasHeight - targetHeight - _containerPadding;
    final x =
        (fromStart
                ? parent.x + _containerChildLeft
                : source.x + _nodeWidth + 88)
            .clamp(parent.x + _containerChildLeft, maxX);
    final y = (fromStart ? parent.y + _containerChildTop : source.y).clamp(
      parent.y + _containerChildTop,
      maxY,
    );
    final occupied = _nodes.where((node) => node.parentNodeId == parentNodeId);
    var candidate = Offset(x, y);
    for (var index = 0; index < 20; index++) {
      final rect = Rect.fromLTWH(
        candidate.dx,
        candidate.dy,
        _nodeWidth,
        targetHeight,
      );
      if (!occupied.any(
        (node) => rect.overlaps(
          Rect.fromLTWH(
            node.x,
            node.y,
            _nodeWidthFor(node),
            _nodeHeightFor(node),
          ).inflate(18),
        ),
      )) {
        return candidate;
      }
      candidate = Offset(
        x,
        (y + (index + 1) * (targetHeight + 28)).clamp(
          parent.y + _containerChildTop,
          maxY,
        ),
      );
    }
    return candidate;
  }

  Offset _nextNodePosition(WorkflowNode source, WorkflowNodeKind targetKind) {
    final targetWidth = isWorkflowContainerKind(targetKind)
        ? _containerMinWidth
        : _nodeWidth;
    final targetHeight = isWorkflowContainerKind(targetKind)
        ? _containerMinHeight
        : targetKind == WorkflowNodeKind.condition
        ? _conditionBranchStart + _conditionBranchSpacing + 32
        : _nodeHeight;
    final maxX = _canvasWidth - targetWidth - 16;
    final maxY = _canvasHeight - targetHeight - 16;
    final x = (source.x + _nodeWidthFor(source) + 110).clamp(16.0, maxX);
    final verticalStep = math.max(_nodeHeightFor(source), targetHeight) + 42;
    for (var index = 0; index < 20; index++) {
      final level = (index + 1) ~/ 2;
      final direction = index == 0 ? 0 : (index.isOdd ? 1 : -1);
      final y = (source.y + level * verticalStep * direction).clamp(16.0, maxY);
      final candidate = Rect.fromLTWH(x, y, targetWidth, targetHeight);
      final occupied = _nodes.any(
        (node) => candidate.overlaps(
          Rect.fromLTWH(
            node.x,
            node.y,
            _nodeWidthFor(node),
            _nodeHeightFor(node),
          ).inflate(24),
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
        WorkflowSettingKeys.conditionCases: <Object?>[
          WorkflowConditionCase(
            id: _uuid.v4(),
            conditions: <WorkflowConditionClause>[
              WorkflowConditionClause(id: _uuid.v4()),
            ],
          ).toJson(),
        ],
      },
      WorkflowNodeKind.loop => <String, Object?>{
        WorkflowSettingKeys.containerWidth: _containerMinWidth,
        WorkflowSettingKeys.containerHeight: _containerMinHeight,
        WorkflowSettingKeys.maxIterations: 10,
        WorkflowSettingKeys.loopVariables: <Object?>[],
        WorkflowSettingKeys.loopBreakConditions: <Object?>[],
        WorkflowSettingKeys.loopConditionLogic:
            WorkflowConditionLogic.all.storageValue,
      },
      WorkflowNodeKind.iteration => <String, Object?>{
        WorkflowSettingKeys.containerWidth: _containerMinWidth,
        WorkflowSettingKeys.containerHeight: _containerMinHeight,
        WorkflowSettingKeys.iterationInput: 'items',
        WorkflowSettingKeys.iterationOutputName: 'iteration_result',
        WorkflowSettingKeys.iterationOutput: '{{item}}',
        WorkflowSettingKeys.iterationParallel: false,
        WorkflowSettingKeys.iterationParallelism: 10,
        WorkflowSettingKeys.iterationErrorMode:
            WorkflowIterationErrorMode.stop.storageValue,
        WorkflowSettingKeys.iterationFlattenOutput: true,
      },
      WorkflowNodeKind.parameterAssignment => <String, Object?>{
        WorkflowSettingKeys.outputFields: <Object?>[],
      },
      WorkflowNodeKind.listOperation => <String, Object?>{
        WorkflowSettingKeys.listInput: '',
        WorkflowSettingKeys.listFilterEnabled: false,
        WorkflowSettingKeys.listFilterKey: '',
        WorkflowSettingKeys.listFilterOperator:
            WorkflowConditionOperator.contains.storageValue,
        WorkflowSettingKeys.listFilterValue: '',
        WorkflowSettingKeys.listFilterValueSource:
            WorkflowValueSource.constant.storageValue,
        WorkflowSettingKeys.listExtractEnabled: false,
        WorkflowSettingKeys.listExtractSerial: '1',
        WorkflowSettingKeys.listOrderEnabled: false,
        WorkflowSettingKeys.listOrderKey: '',
        WorkflowSettingKeys.listOrder: WorkflowListOrder.ascending.storageValue,
        WorkflowSettingKeys.listLimitEnabled: false,
        WorkflowSettingKeys.listLimitSize: 10,
        WorkflowSettingKeys.outputFields: <Object?>[
          WorkflowOutputField(
            id: _uuid.v4(),
            name: _uniqueParameterName('result'),
            description: '处理后的列表',
            type: WorkflowOutputType.array,
          ).toJson(),
          WorkflowOutputField(
            id: _uuid.v4(),
            name: _uniqueParameterName('first_record'),
            description: '处理结果的第一项',
            type: WorkflowOutputType.object,
          ).toJson(),
          WorkflowOutputField(
            id: _uuid.v4(),
            name: _uniqueParameterName('last_record'),
            description: '处理结果的最后一项',
            type: WorkflowOutputType.object,
          ).toJson(),
        ],
      },
      WorkflowNodeKind.loopExit => const <String, Object?>{},
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

  String _uniqueParameterName(String base) {
    final names = _nodes
        .expand((node) => node.declaredParameterFields())
        .map((field) => field.name.trim())
        .toSet();
    if (!names.contains(base)) return base;
    var suffix = 2;
    while (names.contains('${base}_$suffix')) {
      suffix += 1;
    }
    return '${base}_$suffix';
  }

  void _updateNode(
    WorkflowNode updated, {
    String? historyLabel,
    String? mergeKey,
  }) {
    if (!mounted) return;
    setState(() {
      _nodes = _fitContainerSizes(
        _nodes
            .map((node) => node.id == updated.id ? updated : node)
            .toList(growable: false),
      );
      if (updated.kind == WorkflowNodeKind.condition) {
        final branches = _conditionBranches(updated);
        final branchIds = branches.map((branch) => branch.id).toSet();
        _connections = _connections
            .map(
              (connection) =>
                  connection.sourceNodeId == updated.id &&
                      connection.sourceHandleId == null
                  ? WorkflowConnection(
                      id: connection.id,
                      sourceNodeId: connection.sourceNodeId,
                      targetNodeId: connection.targetNodeId,
                      sourceHandleId: branches.first.id,
                    )
                  : connection,
            )
            .where(
              (connection) =>
                  connection.sourceNodeId != updated.id ||
                  connection.sourceHandleId == null ||
                  branchIds.contains(connection.sourceHandleId),
            )
            .toList(growable: false);
      }
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

  void _moveNode(WorkflowNode node, Offset screenDelta) {
    final latest = _nodes.where((item) => item.id == node.id).firstOrNull;
    if (latest == null) return;
    final scale = math.max(
      0.35,
      _transformationController.value.getMaxScaleOnAxis(),
    );
    final delta = screenDelta / scale;
    double nextX;
    double nextY;
    if (latest.parentNodeId != null) {
      final parent = _nodes
          .where((item) => item.id == latest.parentNodeId)
          .firstOrNull;
      if (parent == null) return;
      nextX = (latest.x + delta.dx).clamp(
        parent.x + _containerChildLeft,
        _canvasWidth - _nodeWidthFor(latest) - _containerPadding,
      );
      nextY = (latest.y + delta.dy).clamp(
        parent.y + _containerChildTop,
        _canvasHeight - _nodeHeightFor(latest) - _containerPadding,
      );
    } else {
      nextX = (latest.x + delta.dx).clamp(
        16,
        _canvasWidth - _nodeWidthFor(latest) - 16,
      );
      nextY = (latest.y + delta.dy).clamp(
        16,
        _canvasHeight - _nodeHeightFor(latest) - 16,
      );
    }
    final moved = latest.copyWith(x: nextX, y: nextY);
    final actualDelta = Offset(nextX - latest.x, nextY - latest.y);
    setState(() {
      final nodes = _nodes
          .map((item) {
            if (item.id == moved.id) return moved;
            if (latest.isContainer && item.parentNodeId == latest.id) {
              return item.copyWith(
                x: item.x + actualDelta.dx,
                y: item.y + actualDelta.dy,
              );
            }
            return item;
          })
          .toList(growable: false);
      _nodes = _fitContainerSizes(nodes);
      _recordHistory('移动节点', mergeKey: 'move:${latest.id}');
    });
  }

  void _deleteSelectedNode() {
    final selectedNode = _selectedNode;
    if (selectedNode == null) return;
    if (selectedNode.kind == WorkflowNodeKind.start &&
        _nodes.any(
          (node) => node.parentNodeId == null && node.id != selectedNode.id,
        )) {
      showOpenHandInfoSnack(context, '请先删除其他节点，再删除开始节点。');
      return;
    }
    final removedIds = <String>{
      selectedNode.id,
      if (selectedNode.isContainer)
        ..._nodes
            .where((node) => node.parentNodeId == selectedNode.id)
            .map((node) => node.id),
    };
    setState(() {
      _nodes = _fitContainerSizes(
        _nodes
            .where((node) => !removedIds.contains(node.id))
            .toList(growable: false),
      );
      _connections = _connections
          .where(
            (edge) =>
                !removedIds.contains(edge.sourceNodeId) &&
                !removedIds.contains(edge.targetNodeId),
          )
          .toList(growable: false);
      _selectedNodeId = null;
      _selectedConnectionId = null;
      _testResult = null;
      _testError = null;
      _testStatus = null;
      for (final id in removedIds) {
        _llmConversations.remove(id);
      }
      if (removedIds.contains(_conversationNodeId)) {
        _conversationNodeId = null;
      }
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
      _nodes = _fitContainerSizes(List<WorkflowNode>.from(snapshot.nodes));
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

  void _selectConnection(String connectionId) {
    setState(() {
      _selectedNodeId = null;
      _selectedConnectionId = connectionId;
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
        sourceHandleId: connection.sourceHandleId,
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
        workflowNodes: _nodes,
        workflowConnections: _connections,
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
          onLlmConversation: (conversation) {
            if (!mounted ||
                !_nodes.any((node) => node.id == conversation.nodeId)) {
              return;
            }
            setState(() {
              _llmConversations[conversation.nodeId] = conversation;
            });
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
    _popEditor(
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
      if (node.kind == WorkflowNodeKind.parameterAssignment) {
        try {
          WorkflowStructuredOutputParser.validateFields(
            node.outputFields(),
            label: '赋值参数',
          );
        } catch (error) {
          return '$error';
        }
      }
      if (node.kind == WorkflowNodeKind.listOperation) {
        if (node.stringSetting(WorkflowSettingKeys.listInput).trim().isEmpty) {
          return '列表操作节点的数组输入不能为空。';
        }
        if (node.boolSetting(WorkflowSettingKeys.listFilterEnabled)) {
          final operator = WorkflowConditionOperator.fromStorage(
            node.settings[WorkflowSettingKeys.listFilterOperator],
          );
          final value = node.stringSetting(WorkflowSettingKeys.listFilterValue);
          if (operator.requiresValue && value.trim().isEmpty) {
            return '列表操作节点的筛选比较值不能为空。';
          }
          if (operator.requiresValue) {
            final source = WorkflowValueSource.fromStorage(
              node.settings[WorkflowSettingKeys.listFilterValueSource],
              legacyValue: value,
            );
            final error = validateWorkflowSourcedValue(
              source,
              value,
              label: '列表筛选比较值',
            );
            if (error != null) return error;
          }
        }
        if (node.boolSetting(WorkflowSettingKeys.listExtractEnabled)) {
          final serial = node
              .stringSetting(WorkflowSettingKeys.listExtractSerial, '1')
              .trim();
          final match = workflowTemplatePlaceholderPattern.firstMatch(serial);
          final fullReference =
              match != null && match.start == 0 && match.end == serial.length;
          final parsed = int.tryParse(serial);
          if (!fullReference && (parsed == null || parsed < 1)) {
            return '列表操作节点的提取序号必须是大于等于 1 的整数或参数引用。';
          }
        }
        if (node.boolSetting(WorkflowSettingKeys.listLimitEnabled)) {
          final limit = node.intSetting(WorkflowSettingKeys.listLimitSize, 10);
          if (limit < 1 || limit > maxWorkflowListLimit) {
            return '列表操作节点的最大数量必须在 1–$maxWorkflowListLimit 之间。';
          }
        }
        if (node.outputFields().length != 3) {
          return '列表操作节点必须包含三个输出参数。';
        }
        try {
          WorkflowStructuredOutputParser.validateFields(
            node.outputFields(),
            label: '列表输出参数',
          );
        } catch (error) {
          return '$error';
        }
      }
      if (node.kind == WorkflowNodeKind.loopExit) {
        final parent = _nodes
            .where((item) => item.id == node.parentNodeId)
            .firstOrNull;
        if (parent?.kind != WorkflowNodeKind.loop) {
          return '退出循环节点只能位于循环节点内部。';
        }
        if (_connections.any((edge) => edge.sourceNodeId == node.id)) {
          return '退出循环节点不能连接后续内部节点。';
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
      if (node.kind == WorkflowNodeKind.condition) {
        final cases = node.conditionCases();
        if (cases.isNotEmpty) {
          final conditionError = validateWorkflowConditionCases(cases);
          if (conditionError != null) return conditionError;
        } else if (node
            .stringSetting(WorkflowSettingKeys.expression)
            .trim()
            .isEmpty) {
          return '条件分支至少需要一个 IF 分支。';
        }
      }
      if (node.kind == WorkflowNodeKind.loop) {
        final graphError = _validateContainerGraph(node);
        if (graphError != null) return graphError;
        final count = node.intSetting(WorkflowSettingKeys.maxIterations, 10);
        if (count < 1 || count > 1000) return '最大循环次数必须在 1–1000 之间。';
        final variableError = validateWorkflowLoopVariables(
          node.loopVariables(),
        );
        if (variableError != null) return variableError;
        final breakConditionError = validateWorkflowConditionClauses(
          node.loopBreakConditions(),
          label: '退出条件',
          allowEmpty: true,
        );
        if (breakConditionError != null) return breakConditionError;
      }
      if (node.kind == WorkflowNodeKind.iteration) {
        final graphError = _validateContainerGraph(node);
        if (graphError != null) return graphError;
        if (node
            .stringSetting(WorkflowSettingKeys.iterationInput)
            .trim()
            .isEmpty) {
          return '迭代节点的数组输入不能为空。';
        }
        final outputName = node
            .stringSetting(
              WorkflowSettingKeys.iterationOutputName,
              'iteration_result',
            )
            .trim();
        if (!workflowParameterNamePattern.hasMatch(outputName)) {
          return '迭代节点的输出参数名称无效。';
        }
        if (node
            .stringSetting(WorkflowSettingKeys.iterationOutput, '{{item}}')
            .trim()
            .isEmpty) {
          return '迭代节点的输出映射不能为空。';
        }
        final parallelism = node.intSetting(
          WorkflowSettingKeys.iterationParallelism,
          10,
        );
        if (parallelism < 1 || parallelism > 10) {
          return '迭代节点的最大并行度必须在 1–10 之间。';
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
    final nodesById = <String, WorkflowNode>{
      for (final node in _nodes) node.id: node,
    };
    for (final connection in _connections) {
      final source = nodesById[connection.sourceNodeId];
      final target = nodesById[connection.targetNodeId];
      if (source == null || target == null) return '工作流包含失效连线。';
      if (source.kind == WorkflowNodeKind.loopExit) {
        return '退出循环节点不能连接后续内部节点。';
      }
      final internalStart =
          source.isContainer &&
          connection.sourceHandleId == workflowContainerStartHandleId &&
          target.parentNodeId == source.id;
      final sameNestedScope =
          source.parentNodeId != null &&
          source.parentNodeId == target.parentNodeId;
      final topLevel =
          source.parentNodeId == null &&
          target.parentNodeId == null &&
          connection.sourceHandleId != workflowContainerStartHandleId;
      if (!internalStart && !sameNestedScope && !topLevel) {
        return '节点“${source.title}”存在跨工作流作用域的连线。';
      }
      if (source.kind != WorkflowNodeKind.condition ||
          source.conditionCases().isEmpty) {
        continue;
      }
      final branchIds = _conditionBranches(
        source,
      ).map((branch) => branch.id).toSet();
      if (!branchIds.contains(connection.sourceHandleId)) {
        return '条件节点“${source.title}”存在未指定分支的连线，请重新连接。';
      }
    }
    return validateWorkflowParameterNames(_nodes);
  }

  String? _validateContainerGraph(WorkflowNode container) {
    final children = _nodes
        .where((node) => node.parentNodeId == container.id)
        .toList(growable: false);
    if (children.isEmpty) return '节点“${container.title}”至少需要一个内部执行节点。';
    if (children.length > maxWorkflowNestedNodeCount) {
      return '节点“${container.title}”的内部节点不能超过 $maxWorkflowNestedNodeCount 个。';
    }
    final childIds = children.map((node) => node.id).toSet();
    final starts = _connections
        .where(
          (edge) =>
              edge.sourceNodeId == container.id &&
              edge.sourceHandleId == workflowContainerStartHandleId &&
              childIds.contains(edge.targetNodeId),
        )
        .map((edge) => edge.targetNodeId)
        .toList(growable: false);
    if (starts.isEmpty) return '节点“${container.title}”的内部起点尚未连接执行节点。';
    final reachable = <String>{};
    final pending = <String>[...starts];
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      if (!reachable.add(current)) continue;
      for (final edge in _connections) {
        if (edge.sourceNodeId == current &&
            childIds.contains(edge.targetNodeId)) {
          pending.add(edge.targetNodeId);
        }
      }
    }
    final unreachable = children.where((node) => !reachable.contains(node.id));
    if (unreachable.isNotEmpty) {
      return '节点“${container.title}”包含未连接的内部节点“${unreachable.first.title}”。';
    }
    final childEdges = _connections
        .where(
          (edge) =>
              childIds.contains(edge.sourceNodeId) &&
              childIds.contains(edge.targetNodeId),
        )
        .toList(growable: false);
    final incomingCounts = <String, int>{
      for (final child in children) child.id: 0,
    };
    for (final edge in childEdges) {
      incomingCounts[edge.targetNodeId] =
          incomingCounts[edge.targetNodeId]! + 1;
    }
    final ready = children
        .where((child) => incomingCounts[child.id] == 0)
        .map((child) => child.id)
        .toList(growable: true);
    var sortedCount = 0;
    while (ready.isNotEmpty) {
      final current = ready.removeLast();
      sortedCount += 1;
      for (final edge in childEdges) {
        if (edge.sourceNodeId != current) continue;
        final remaining = incomingCounts[edge.targetNodeId]! - 1;
        incomingCounts[edge.targetNodeId] = remaining;
        if (remaining == 0) ready.add(edge.targetNodeId);
      }
    }
    if (sortedCount != children.length) {
      return '节点“${container.title}”的内部工作流不能包含循环连线。';
    }
    return null;
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
    final parent = target.parentNodeId == null
        ? null
        : _nodes.where((node) => node.id == target.parentNodeId).firstOrNull;
    final references = _nodes
        .where(
          (node) =>
              upstreamIds.contains(node.id) &&
              (parent == null || node.id != parent.id),
        )
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
        .toList(growable: true);
    if (parent?.kind == WorkflowNodeKind.iteration) {
      for (final field in const <WorkflowOutputField>[
        WorkflowOutputField(
          id: 'iteration-item',
          name: 'item',
          description: '当前数组项',
          type: WorkflowOutputType.object,
        ),
        WorkflowOutputField(
          id: 'iteration-index',
          name: 'index',
          description: '当前索引',
          type: WorkflowOutputType.integer,
        ),
        WorkflowOutputField(
          id: 'iteration-length',
          name: 'length',
          description: '数组长度',
          type: WorkflowOutputType.integer,
        ),
      ]) {
        if (names.add(field.name)) {
          references.add(
            WorkflowParameterReference(
              nodeId: parent!.id,
              nodeTitle: '当前迭代',
              field: field,
            ),
          );
        }
      }
    } else if (parent?.kind == WorkflowNodeKind.loop) {
      for (final field in <WorkflowOutputField>[
        ...parent!.declaredParameterFields(),
        const WorkflowOutputField(
          id: 'loop-index',
          name: 'loop_index',
          description: '当前循环索引',
          type: WorkflowOutputType.integer,
        ),
      ]) {
        if (names.add(field.name)) {
          references.add(
            WorkflowParameterReference(
              nodeId: parent.id,
              nodeTitle: '当前循环',
              field: field,
            ),
          );
        }
      }
    }
    return List<WorkflowParameterReference>.unmodifiable(references);
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

  List<WorkflowParameterReference> _nestedOutputReferencesFor(
    WorkflowNode container,
  ) {
    if (!container.isContainer) {
      return const <WorkflowParameterReference>[];
    }
    final names = <String>{};
    return _nodes
        .where((node) => node.parentNodeId == container.id)
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
          WorkflowOutputType.arrayString => <String>['第一项', '第二项'],
          WorkflowOutputType.arrayNumber => <num>[1, 2],
          WorkflowOutputType.arrayObject => <Map<String, Object?>>[
            <String, Object?>{'key': 'value'},
          ],
          WorkflowOutputType.arrayBoolean => <bool>[true, false],
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
    required this.scopeParentId,
    required this.canvasOrigin,
    required this.selectedConnectionId,
    required this.draftSourceNodeId,
    required this.draftSourceHandleId,
    required this.draftTargetNodeId,
    required this.draftEnd,
    required this.draftValid,
    required this.color,
    required this.errorColor,
    required this.mutedColor,
  });

  final List<WorkflowNode> nodes;
  final List<WorkflowConnection> connections;
  final String? scopeParentId;
  final Offset canvasOrigin;
  final String? selectedConnectionId;
  final String? draftSourceNodeId;
  final String? draftSourceHandleId;
  final String? draftTargetNodeId;
  final Offset? draftEnd;
  final bool draftValid;
  final Color color;
  final Color errorColor;
  final Color mutedColor;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(-canvasOrigin.dx, -canvasOrigin.dy);
    final byId = <String, WorkflowNode>{
      for (final node in nodes) node.id: node,
    };
    for (final edge in connections) {
      final source = byId[edge.sourceNodeId];
      final target = byId[edge.targetNodeId];
      if (source == null ||
          target == null ||
          _workflowConnectionScope(source, edge.sourceHandleId) !=
              scopeParentId) {
        continue;
      }
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
      final start = _workflowConnectionStart(
        source,
        sourceHandleId: edge.sourceHandleId,
      );
      final end = _workflowConnectionEnd(target);
      final distance = math.max(70, (end.dx - start.dx).abs() * 0.46);
      final path = _workflowConnectionPath(
        source,
        target,
        sourceHandleId: edge.sourceHandleId,
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

    final draftSource = byId[draftSourceNodeId];
    final pointerEnd = draftEnd;
    if (draftSource == null ||
        pointerEnd == null ||
        _workflowConnectionScope(draftSource, draftSourceHandleId) !=
            scopeParentId) {
      canvas.restore();
      return;
    }
    final draftTarget = byId[draftTargetNodeId];
    final start = _workflowConnectionStart(
      draftSource,
      sourceHandleId: draftSourceHandleId,
      containerHasChildren: nodes.any(
        (node) => node.parentNodeId == draftSource.id,
      ),
    );
    final end = draftTarget == null
        ? pointerEnd
        : _workflowConnectionEnd(draftTarget);
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
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WorkflowConnectionPainter oldDelegate) {
    return nodes != oldDelegate.nodes ||
        connections != oldDelegate.connections ||
        scopeParentId != oldDelegate.scopeParentId ||
        canvasOrigin != oldDelegate.canvasOrigin ||
        selectedConnectionId != oldDelegate.selectedConnectionId ||
        draftSourceNodeId != oldDelegate.draftSourceNodeId ||
        draftSourceHandleId != oldDelegate.draftSourceHandleId ||
        draftTargetNodeId != oldDelegate.draftTargetNodeId ||
        draftEnd != oldDelegate.draftEnd ||
        draftValid != oldDelegate.draftValid ||
        color != oldDelegate.color ||
        errorColor != oldDelegate.errorColor ||
        mutedColor != oldDelegate.mutedColor;
  }
}

Path _workflowConnectionPath(
  WorkflowNode source,
  WorkflowNode target, {
  String? sourceHandleId,
}) {
  final start = _workflowConnectionStart(
    source,
    sourceHandleId: sourceHandleId,
  );
  final end = _workflowConnectionEnd(target);
  return _workflowConnectionPathBetween(start, end);
}

Offset _workflowConnectionStart(
  WorkflowNode source, {
  String? sourceHandleId,
  bool containerHasChildren = true,
}) {
  if (source.isContainer && sourceHandleId == workflowContainerStartHandleId) {
    return Offset(
      source.x + 76 + _nodeAddButtonHitSize / 2,
      source.y +
          _containerStartCenterY(
            containerHeight: _nodeHeightFor(source),
            hasChildren: containerHasChildren,
          ),
    );
  }
  if (source.kind == WorkflowNodeKind.condition && sourceHandleId != null) {
    final index = _conditionBranches(
      source,
    ).indexWhere((branch) => branch.id == sourceHandleId);
    if (index >= 0) {
      return Offset(
        source.x + _nodeWidthFor(source),
        source.y + _conditionBranchStart + index * _conditionBranchSpacing,
      );
    }
  }
  return Offset(
    source.x + _nodeWidthFor(source),
    source.y +
        (source.isContainer
            ? _containerHeaderHeight / 2
            : _nodeHeightFor(source) / 2),
  );
}

double _containerStartCenterY({
  required double containerHeight,
  required bool hasChildren,
}) => hasChildren
    ? _containerChildTop + _nodeHeight / 2
    : (_containerHeaderHeight + containerHeight) / 2;

Offset _workflowConnectionEnd(WorkflowNode target) => Offset(
  target.x,
  target.y +
      (target.isContainer
          ? _containerHeaderHeight / 2
          : _nodeHeightFor(target) / 2),
);

String? _workflowConnectionScope(WorkflowNode source, String? sourceHandleId) =>
    source.isContainer && sourceHandleId == workflowContainerStartHandleId
    ? source.id
    : source.parentNodeId;

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

List<({String id, String label})> _conditionBranches(WorkflowNode node) {
  final cases = node.conditionCases();
  return <({String id, String label})>[
    if (cases.isEmpty)
      (id: 'legacy-if', label: 'IF')
    else
      for (final item in cases.indexed)
        (id: item.$2.id, label: item.$1 == 0 ? 'IF' : 'ELIF ${item.$1}'),
    (id: 'else', label: 'ELSE'),
  ];
}

List<WorkflowNode> _fitContainerSizes(List<WorkflowNode> nodes) {
  final childrenByParent = <String, List<WorkflowNode>>{};
  for (final node in nodes) {
    final parentId = node.parentNodeId;
    if (parentId != null) {
      (childrenByParent[parentId] ??= <WorkflowNode>[]).add(node);
    }
  }
  return nodes
      .map((node) {
        if (!node.isContainer) return node;
        var width = _containerMinWidth;
        var height = _containerMinHeight;
        for (final child
            in childrenByParent[node.id] ?? const <WorkflowNode>[]) {
          width = math.max(
            width,
            child.x + _nodeWidthFor(child) - node.x + _containerPadding,
          );
          height = math.max(
            height,
            child.y + _nodeHeightFor(child) - node.y + _containerPadding,
          );
        }
        width = math.min(width, _canvasWidth - node.x - 16);
        height = math.min(height, _canvasHeight - node.y - 16);
        if (width ==
                node.doubleSetting(
                  WorkflowSettingKeys.containerWidth,
                  _containerMinWidth,
                ) &&
            height ==
                node.doubleSetting(
                  WorkflowSettingKeys.containerHeight,
                  _containerMinHeight,
                )) {
          return node;
        }
        return node.copyWith(
          settings: Map<String, Object?>.unmodifiable(<String, Object?>{
            ...node.settings,
            WorkflowSettingKeys.containerWidth: width,
            WorkflowSettingKeys.containerHeight: height,
          }),
        );
      })
      .toList(growable: false);
}

double _nodeHeightFor(WorkflowNode node) {
  if (node.isContainer) {
    return math.max(
      _containerMinHeight,
      node.doubleSetting(
        WorkflowSettingKeys.containerHeight,
        _containerMinHeight,
      ),
    );
  }
  if (node.kind != WorkflowNodeKind.condition) return _nodeHeight;
  final branchCount = _conditionBranches(node).length;
  return math.max(
    _nodeHeight,
    _conditionBranchStart + (branchCount - 1) * _conditionBranchSpacing + 32,
  );
}

double _nodeWidthFor(WorkflowNode node) => node.isContainer
    ? math.max(
        _containerMinWidth,
        node.doubleSetting(
          WorkflowSettingKeys.containerWidth,
          _containerMinWidth,
        ),
      )
    : _nodeWidth;

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
    WorkflowNodeKind.condition =>
      node.conditionCases().isEmpty
          ? node.stringSetting(WorkflowSettingKeys.expression)
          : '${node.conditionCases().length} 个条件分支 · ELSE',
    WorkflowNodeKind.loop =>
      '${node.loopVariables().length} 个循环变量 · 最多 ${node.intSetting(WorkflowSettingKeys.maxIterations, 10)} 次',
    WorkflowNodeKind.iteration =>
      '${node.boolSetting(WorkflowSettingKeys.iterationParallel) ? '并行' : '串行'}迭代 · ${node.stringSetting(WorkflowSettingKeys.iterationOutputName, 'iteration_result')}',
    WorkflowNodeKind.parameterAssignment =>
      node.outputFields().isEmpty
          ? '添加需要赋值的输出参数'
          : '${node.outputFields().length} 个赋值参数',
    WorkflowNodeKind.listOperation =>
      '${node.boolSetting(WorkflowSettingKeys.listFilterEnabled) ? '筛选 · ' : ''}${node.boolSetting(WorkflowSettingKeys.listOrderEnabled) ? '排序 · ' : ''}${node.boolSetting(WorkflowSettingKeys.listLimitEnabled) ? '限量' : '输出列表'}',
    WorkflowNodeKind.loopExit => '立即结束当前循环',
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

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/workflows/model/workflow_definition.dart';
import 'package:openhand/features/workflows/service/workflow_auto_layout.dart';

void main() {
  const sizeOf = _fixedNodeSize;

  test('分层整理保持流向、分支顺序且结果稳定', () {
    const nodes = <WorkflowNode>[
      WorkflowNode(
        id: 'end',
        kind: WorkflowNodeKind.end,
        title: '结束',
        x: 90,
        y: 80,
      ),
      WorkflowNode(
        id: 'failure',
        kind: WorkflowNodeKind.codeExecution,
        title: '异常处理',
        x: 120,
        y: 500,
      ),
      WorkflowNode(
        id: 'start',
        kind: WorkflowNodeKind.start,
        title: '开始',
        x: 900,
        y: 700,
      ),
      WorkflowNode(
        id: 'branch',
        kind: WorkflowNodeKind.codeExecution,
        title: '代码执行',
        x: 400,
        y: 300,
        settings: <String, Object?>{
          WorkflowSettingKeys.errorStrategy: 'fail-branch',
        },
      ),
      WorkflowNode(
        id: 'success',
        kind: WorkflowNodeKind.llm,
        title: '成功处理',
        x: 160,
        y: 120,
      ),
    ];
    const connections = <WorkflowConnection>[
      WorkflowConnection(
        id: '1',
        sourceNodeId: 'start',
        targetNodeId: 'branch',
      ),
      WorkflowConnection(
        id: '2',
        sourceNodeId: 'branch',
        targetNodeId: 'success',
        sourceHandleId: workflowSuccessHandleId,
      ),
      WorkflowConnection(
        id: '3',
        sourceNodeId: 'branch',
        targetNodeId: 'failure',
        sourceHandleId: workflowFailureHandleId,
      ),
      WorkflowConnection(id: '4', sourceNodeId: 'success', targetNodeId: 'end'),
      WorkflowConnection(id: '5', sourceNodeId: 'failure', targetNodeId: 'end'),
    ];

    final result = arrangeWorkflowNodes(
      nodes: nodes,
      connections: connections,
      sizeOf: sizeOf,
    );
    final arranged = <String, WorkflowNode>{
      for (final node in result.nodes) node.id: node,
    };
    expect(result.fitsCanvas, isTrue);
    expect(result.changed, isTrue);
    expect(arranged['start']!.x, lessThan(arranged['branch']!.x));
    expect(arranged['branch']!.x, lessThan(arranged['success']!.x));
    expect(arranged['success']!.x, arranged['failure']!.x);
    expect(arranged['success']!.y, lessThan(arranged['failure']!.y));
    expect(arranged['failure']!.x, lessThan(arranged['end']!.x));

    final repeated = arrangeWorkflowNodes(
      nodes: result.nodes,
      connections: connections,
      sizeOf: sizeOf,
    );
    expect(repeated.changed, isFalse);
    expect(
      repeated.nodes.map((node) => (node.id, node.x, node.y)),
      result.nodes.map((node) => (node.id, node.x, node.y)),
    );
  });

  test('循环容器与内部节点分别布局并同步扩展容器', () {
    const nodes = <WorkflowNode>[
      WorkflowNode(
        id: 'start',
        kind: WorkflowNodeKind.start,
        title: '开始',
        x: 900,
        y: 700,
      ),
      WorkflowNode(
        id: 'loop',
        kind: WorkflowNodeKind.loop,
        title: '循环',
        x: 100,
        y: 80,
      ),
      WorkflowNode(
        id: 'child-1',
        kind: WorkflowNodeKind.codeExecution,
        title: '内部处理',
        x: 700,
        y: 600,
        parentNodeId: 'loop',
      ),
      WorkflowNode(
        id: 'child-2',
        kind: WorkflowNodeKind.loopExit,
        title: '退出循环',
        x: 200,
        y: 500,
        parentNodeId: 'loop',
      ),
      WorkflowNode(
        id: 'end',
        kind: WorkflowNodeKind.end,
        title: '结束',
        x: 300,
        y: 200,
      ),
    ];
    const connections = <WorkflowConnection>[
      WorkflowConnection(id: '1', sourceNodeId: 'start', targetNodeId: 'loop'),
      WorkflowConnection(
        id: '2',
        sourceNodeId: 'loop',
        targetNodeId: 'child-1',
        sourceHandleId: workflowContainerStartHandleId,
      ),
      WorkflowConnection(
        id: '3',
        sourceNodeId: 'child-1',
        targetNodeId: 'child-2',
      ),
      WorkflowConnection(id: '4', sourceNodeId: 'loop', targetNodeId: 'end'),
    ];

    final result = arrangeWorkflowNodes(
      nodes: nodes,
      connections: connections,
      sizeOf: (node) => node.isContainer
          ? (
              width: node.doubleSetting(
                WorkflowSettingKeys.containerWidth,
                360,
              ),
              height: node.doubleSetting(
                WorkflowSettingKeys.containerHeight,
                196,
              ),
            )
          : _fixedNodeSize(node),
    );
    final arranged = <String, WorkflowNode>{
      for (final node in result.nodes) node.id: node,
    };
    final loop = arranged['loop']!;
    final first = arranged['child-1']!;
    final second = arranged['child-2']!;
    expect(result.fitsCanvas, isTrue);
    expect(
      loop.doubleSetting(WorkflowSettingKeys.containerWidth, 0),
      greaterThan(360),
    );
    expect(first.x, greaterThanOrEqualTo(loop.x + 132));
    expect(first.y, greaterThanOrEqualTo(loop.y + 96));
    expect(second.x, greaterThan(first.x));
    expect(
      second.x + 100,
      lessThanOrEqualTo(
        loop.x + loop.doubleSetting(WorkflowSettingKeys.containerWidth, 0) - 34,
      ),
    );
    expect(arranged['start']!.x, lessThan(loop.x));
    expect(loop.x, lessThan(arranged['end']!.x));
  });

  test('画布无法容纳时明确返回失败且循环连线不会卡死', () {
    final nodes = List<WorkflowNode>.generate(
      8,
      (index) => WorkflowNode(
        id: 'node-$index',
        kind: index == 0
            ? WorkflowNodeKind.start
            : index == 7
            ? WorkflowNodeKind.end
            : WorkflowNodeKind.codeExecution,
        title: '节点 $index',
        x: 0,
        y: 0,
      ),
    );
    final connections = <WorkflowConnection>[
      for (var index = 0; index < 7; index++)
        WorkflowConnection(
          id: 'edge-$index',
          sourceNodeId: 'node-$index',
          targetNodeId: 'node-${index + 1}',
        ),
      const WorkflowConnection(
        id: 'cycle',
        sourceNodeId: 'node-7',
        targetNodeId: 'node-3',
      ),
      const WorkflowConnection(
        id: 'invalid',
        sourceNodeId: 'missing',
        targetNodeId: 'node-0',
      ),
    ];

    final result = arrangeWorkflowNodes(
      nodes: nodes,
      connections: connections,
      sizeOf: sizeOf,
      config: const WorkflowAutoLayoutConfig(
        canvasWidth: 500,
        canvasHeight: 300,
        canvasPadding: 20,
      ),
    );
    expect(result.fitsCanvas, isFalse);
    expect(result.nodes, hasLength(nodes.length));
    expect(
      result.nodes.map((node) => node.id).toSet(),
      hasLength(nodes.length),
    );
  });
}

({double width, double height}) _fixedNodeSize(WorkflowNode _) =>
    (width: 100, height: 60);

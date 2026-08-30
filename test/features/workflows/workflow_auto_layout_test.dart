import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/workflows/model/workflow_definition.dart';
import 'package:openhand/features/workflows/service/workflow_auto_layout.dart';

void main() {
  test('整理节点时同步移动注释并保持相对位置', () {
    const nodes = <WorkflowNode>[
      WorkflowNode(
        id: 'start',
        kind: WorkflowNodeKind.start,
        title: '开始',
        x: 560,
        y: 120,
      ),
      WorkflowNode(
        id: 'code',
        kind: WorkflowNodeKind.codeExecution,
        title: '代码执行',
        x: 900,
        y: 300,
      ),
      WorkflowNode(
        id: 'end',
        kind: WorkflowNodeKind.end,
        title: '结束',
        x: 180,
        y: 700,
      ),
    ];
    const annotations = <WorkflowAnnotation>[
      WorkflowAnnotation(id: 'note', text: '代码说明', x: 880, y: 440),
    ];
    const connections = <WorkflowConnection>[
      WorkflowConnection(
        id: 'start-code',
        sourceNodeId: 'start',
        targetNodeId: 'code',
      ),
      WorkflowConnection(
        id: 'code-end',
        sourceNodeId: 'code',
        targetNodeId: 'end',
      ),
    ];

    final result = arrangeWorkflowNodes(
      nodes: nodes,
      connections: connections,
      annotations: annotations,
      sizeOf: _fixedNodeSize,
    );
    final arranged = <String, WorkflowNode>{
      for (final node in result.nodes) node.id: node,
    };
    final code = arranged['code']!;
    final note = result.annotations.single;

    expect(result.changed, isTrue);
    expect(note.x, closeTo(annotations.single.x + code.x - 900, 0.01));
    expect(note.y, closeTo(annotations.single.y + code.y - 300, 0.01));
    expect(note.y, greaterThanOrEqualTo(code.y + 60));
    expect(result.left, lessThanOrEqualTo(note.x));
    expect(result.top, lessThanOrEqualTo(note.y));
    expect(result.right, greaterThanOrEqualTo(note.x + note.width));
    expect(result.bottom, greaterThanOrEqualTo(note.y + note.height));

    final repeated = arrangeWorkflowNodes(
      nodes: result.nodes,
      connections: connections,
      annotations: result.annotations,
      sizeOf: _fixedNodeSize,
    );
    expect(repeated.changed, isFalse);
    expect(repeated.annotations.single.x, note.x);
    expect(repeated.annotations.single.y, note.y);
  });
}

({double width, double height}) _fixedNodeSize(WorkflowNode _) =>
    (width: 100, height: 60);

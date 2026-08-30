import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/workflows/model/workflow_definition.dart';
import 'package:openhand/features/workflows/service/workflow_auto_layout.dart';

void main() {
  test('整理时保留未被遮挡注释的原位置', () {
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
      WorkflowAnnotation(id: 'note', text: '代码说明', x: 880, y: 1000),
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
    final note = result.annotations.single;

    expect(result.changed, isTrue);
    expect(note.x, annotations.single.x);
    expect(note.y, annotations.single.y);
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

  test('整理会将遮挡节点的注释放入相邻空白区域', () {
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
      WorkflowAnnotation(id: 'note', text: '代码说明', x: 270, y: 48),
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
    final annotation = result.annotations.single;

    expect(result.fitsCanvas, isTrue);
    expect(
      annotation.x != annotations.single.x ||
          annotation.y != annotations.single.y,
      isTrue,
    );
    for (final node in result.nodes) {
      expect(
        _overlaps(
          annotation.x,
          annotation.y,
          annotation.width,
          annotation.height,
          node.x,
          node.y,
          100,
          60,
        ),
        isFalse,
      );
    }
  });

  test('整理会避开穿过注释的连线', () {
    const nodes = <WorkflowNode>[
      WorkflowNode(
        id: 'start',
        kind: WorkflowNodeKind.start,
        title: '开始',
        x: 560,
        y: 120,
      ),
      WorkflowNode(
        id: 'end',
        kind: WorkflowNodeKind.end,
        title: '结束',
        x: 900,
        y: 120,
      ),
    ];
    const annotations = <WorkflowAnnotation>[
      WorkflowAnnotation(
        id: 'note',
        text: '连线说明',
        x: 180,
        y: 68,
        width: 20,
        height: 20,
      ),
    ];
    const connections = <WorkflowConnection>[
      WorkflowConnection(
        id: 'start-end',
        sourceNodeId: 'start',
        targetNodeId: 'end',
      ),
    ];

    final result = arrangeWorkflowNodes(
      nodes: nodes,
      connections: connections,
      annotations: annotations,
      sizeOf: _fixedNodeSize,
    );
    final annotation = result.annotations.single;

    expect(result.fitsCanvas, isTrue);
    expect(
      annotation.x != annotations.single.x ||
          annotation.y != annotations.single.y,
      isTrue,
    );
    final arranged = <String, WorkflowNode>{
      for (final node in result.nodes) node.id: node,
    };
    final start = arranged['start']!;
    final end = arranged['end']!;
    expect(
      _horizontalLineIntersects(annotation, start.x + 100, start.y + 30, end.x),
      isFalse,
    );
  });
}

({double width, double height}) _fixedNodeSize(WorkflowNode _) =>
    (width: 100, height: 60);

bool _overlaps(
  double left,
  double top,
  double width,
  double height,
  double otherLeft,
  double otherTop,
  double otherWidth,
  double otherHeight,
) =>
    left < otherLeft + otherWidth &&
    left + width > otherLeft &&
    top < otherTop + otherHeight &&
    top + height > otherTop;

bool _horizontalLineIntersects(
  WorkflowAnnotation annotation,
  double startX,
  double y,
  double endX,
) =>
    y >= annotation.y &&
    y <= annotation.y + annotation.height &&
    startX <= annotation.x + annotation.width &&
    endX >= annotation.x;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/workflows/model/workflow_definition.dart';
import 'package:openhand/features/workflows/widgets/workflow_parameter_reference_field.dart';

const _inputReference = WorkflowParameterReference(
  nodeId: 'code-node',
  nodeTitle: '代码执行',
  field: WorkflowOutputField(
    id: 'input-field',
    name: 'arg1',
    description: '入参',
  ),
  direction: WorkflowParameterDirection.input,
);

const _outputReference = WorkflowParameterReference(
  nodeId: 'code-node',
  nodeTitle: '代码执行',
  field: WorkflowOutputField(
    id: 'output-field',
    name: 'result',
    description: '执行结果',
  ),
  direction: WorkflowParameterDirection.output,
);

void main() {
  testWidgets('参数类型标签使用全局主色容器', (tester) async {
    final colorScheme = ColorScheme.fromSeed(seedColor: Colors.green);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: colorScheme),
        home: Scaffold(
          body: WorkflowParameterReferenceField(
            value: '',
            references: const <WorkflowParameterReference>[_outputReference],
            decoration: const InputDecoration(labelText: '参数值'),
            onChanged: (_) {},
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).first, '/');
    await tester.pumpAndSettle();

    final badge = tester
        .widgetList<Container>(find.byType(Container))
        .firstWhere(
          (container) =>
              container.child is Text &&
              (container.child! as Text).data ==
                  _outputReference.field.type.label,
        );
    final decoration = badge.decoration! as BoxDecoration;
    expect(
      decoration.color,
      colorScheme.primaryContainer.withValues(alpha: 0.58),
    );
  });

  testWidgets('候选浮窗按输入输出子组区分参数并跟随主题色', (tester) async {
    final colorScheme = ColorScheme.fromSeed(seedColor: const Color(0xFF4F7B6A));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: colorScheme),
        home: Scaffold(
          body: WorkflowParameterReferenceField(
            value: '',
            references: const <WorkflowParameterReference>[
              _inputReference,
              _outputReference,
            ],
            decoration: const InputDecoration(labelText: '参数值'),
            onChanged: (_) {},
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).first, '/');
    await tester.pumpAndSettle();

    expect(find.text('代码执行'.toUpperCase()), findsOneWidget);
    expect(find.text('输入参数'), findsOneWidget);
    expect(find.text('输出参数'), findsOneWidget);
    expect(find.text('arg1'), findsOneWidget);
    expect(find.text('result'), findsOneWidget);

    final inputHeaderOffset = tester.getTopLeft(find.text('输入参数'));
    final argOffset = tester.getTopLeft(find.text('arg1'));
    final outputHeaderOffset = tester.getTopLeft(find.text('输出参数'));
    final resultOffset = tester.getTopLeft(find.text('result'));
    expect(inputHeaderOffset.dy, lessThan(argOffset.dy));
    expect(argOffset.dy, lessThan(outputHeaderOffset.dy));
    expect(outputHeaderOffset.dy, lessThan(resultOffset.dy));

    final inputLabel = tester.widget<Text>(find.text('输入参数'));
    final outputLabel = tester.widget<Text>(find.text('输出参数'));
    expect(outputLabel.style?.color, colorScheme.primary);
    expect(
      inputLabel.style?.color,
      Color.lerp(colorScheme.primary, colorScheme.onSurface, 0.38),
    );
    expect(inputLabel.style?.color, isNot(colorScheme.secondary));
  });

  test('collectWorkflowParameterReferences 按方向归类并去重', () {
    const node = WorkflowNode(
      id: 'code',
      kind: WorkflowNodeKind.codeExecution,
      title: '代码执行',
      x: 0,
      y: 0,
      settings: <String, Object?>{
        WorkflowSettingKeys.codeInputFields: <Object?>[
          <String, Object?>{'id': 'in-1', 'name': 'arg1'},
          <String, Object?>{'id': 'in-2', 'name': 'arg1'},
        ],
        WorkflowSettingKeys.outputFields: <Object?>[
          <String, Object?>{'id': 'out-1', 'name': 'result'},
        ],
      },
    );
    final names = <String>{};
    final references = collectWorkflowParameterReferences(
      node,
      usedNames: names,
    );
    expect(references, hasLength(2));
    expect(references.first.name, 'arg1');
    expect(references.first.direction, WorkflowParameterDirection.input);
    expect(references.last.name, 'result');
    expect(references.last.direction, WorkflowParameterDirection.output);
  });

  test('workflowUpstreamHopDistances 返回由近到远的最小跳数', () {
    const connections = <WorkflowConnection>[
      WorkflowConnection(
        id: 'e1',
        sourceNodeId: 'start',
        targetNodeId: 'code',
      ),
      WorkflowConnection(
        id: 'e2',
        sourceNodeId: 'code',
        targetNodeId: 'end',
      ),
      WorkflowConnection(
        id: 'e3',
        sourceNodeId: 'llm',
        targetNodeId: 'end',
      ),
      WorkflowConnection(
        id: 'e4',
        sourceNodeId: 'start',
        targetNodeId: 'llm',
      ),
    ];
    final distances = workflowUpstreamHopDistances(
      targetNodeId: 'end',
      connections: connections,
    );
    expect(distances['code'], 1);
    expect(distances['llm'], 1);
    expect(distances['start'], 2);
    expect(distances.containsKey('end'), isFalse);

    final ordered = distances.entries.toList()
      ..sort((left, right) {
        final hopCompare = left.value.compareTo(right.value);
        if (hopCompare != 0) return hopCompare;
        return left.key.compareTo(right.key);
      });
    expect(
      ordered.map((entry) => entry.key).toList(),
      <String>['code', 'llm', 'start'],
    );
  });
}

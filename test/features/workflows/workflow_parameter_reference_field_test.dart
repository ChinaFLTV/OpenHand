import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/workflows/model/workflow_definition.dart';
import 'package:openhand/features/workflows/widgets/workflow_parameter_reference_field.dart';

const _reference = WorkflowParameterReference(
  nodeId: 'upstream-node',
  nodeTitle: '上游节点',
  field: WorkflowOutputField(
    id: 'output-field',
    name: 'result',
    description: '执行结果',
  ),
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
            references: const <WorkflowParameterReference>[_reference],
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
              (container.child! as Text).data == _reference.field.type.label,
        );
    final decoration = badge.decoration! as BoxDecoration;
    expect(
      decoration.color,
      colorScheme.primaryContainer.withValues(alpha: 0.58),
    );
  });
}

import 'dart:io';
import 'support/flutter_widget_check.dart';

Future<void> main() => runFlutterWidgetCheck(
  root: File.fromUri(Platform.script).parent.parent,
  name: 'workflow_reference_types',
  source: '''
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/workflows/model/workflow_definition.dart';

void main() {
  String? validate(WorkflowOutputType source, WorkflowOutputType target,
      {String value = '{{upstream}}', WorkflowValueMode mode = WorkflowValueMode.literal}) {
    final nodes = [
      WorkflowNode(id: 'start', kind: WorkflowNodeKind.start, title: '输入来源', x: 0, y: 0,
        settings: {WorkflowSettingKeys.inputFields: [WorkflowOutputField(id: 'upstream', name: 'upstream', type: source).toJson()]}),
      WorkflowNode(id: 'target', kind: WorkflowNodeKind.codeExecution, title: '目标节点', x: 300, y: 0,
        settings: {WorkflowSettingKeys.codeInputFields: [WorkflowOutputField(id: 'target', name: 'argument', type: target, value: value, valueMode: mode).toJson()]}),
    ];
    return validateWorkflowParameters(nodes, const [WorkflowConnection(id: 'edge', sourceNodeId: 'start', targetNodeId: 'target')]);
  }
  test('纯引用严格匹配所有声明类型，不对不匹配类型隐式放行', () {
    for (final source in WorkflowOutputType.values) {
      for (final target in WorkflowOutputType.values) {
        final error = validate(source, target);
        if (source == target) {
          expect(error, isNull);
        } else {
          expect(error, contains('类型'));
          expect(error, contains('argument'));
          expect(error, contains('upstream'));
          expect(error, contains(source.label));
          expect(error, contains(target.label));
        }
      }
    }
  });
  test('拼接和表达式不按纯引用校验，失效引用仍驳回', () {
    expect(validate(WorkflowOutputType.arrayString, WorkflowOutputType.string, value: '结果：{{upstream}}'), isNull);
    expect(validate(WorkflowOutputType.arrayString, WorkflowOutputType.string, mode: WorkflowValueMode.pythonExpression), isNull);
    expect(validate(WorkflowOutputType.string, WorkflowOutputType.string, value: '{{missing}}'), contains('不存在'));
  });
}
''',
);

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/workflows/model/workflow_definition.dart';
import 'package:openhand/features/workflows/service/workflow_development_parameters.dart';
import 'package:openhand/features/workflows/service/workflow_node_executor.dart';

void main() {
  test('同步开始节点参数时保留已有临时值', () {
    const start = WorkflowNode(
      id: 'start',
      kind: WorkflowNodeKind.start,
      title: '开始',
      x: 0,
      y: 0,
      settings: <String, Object?>{
        WorkflowSettingKeys.inputFields: <Object?>[
          <String, Object?>{
            'id': 'question',
            'name': 'question',
            'type': 'string',
          },
          <String, Object?>{'id': 'count', 'name': 'count', 'type': 'integer'},
        ],
      },
    );
    final result = synchronizeWorkflowDevelopmentStartParameters(
      parameters: <WorkflowDevelopmentParameter>[
        const WorkflowDevelopmentParameter(
          id: 'start-question',
          field: WorkflowOutputField(id: 'question', name: 'question'),
          source: WorkflowDevelopmentParameterSource.startInput,
          ownerNodeId: 'start',
          value: '你好',
        ),
        const WorkflowDevelopmentParameter(
          id: 'manual-token',
          field: WorkflowOutputField(id: 'token', name: 'token'),
          source: WorkflowDevelopmentParameterSource.manual,
          value: 'abc',
        ),
      ],
      startNode: start,
    );

    expect(result.map((parameter) => parameter.name), <String>[
      'question',
      'count',
      'token',
    ]);
    expect(result.first.value, '你好');
    expect(result[1].value, isEmpty);
    expect(result.last.source, WorkflowDevelopmentParameterSource.manual);
  });

  test('解析临时参数的引用和类型', () {
    const parameters = <WorkflowDevelopmentParameter>[
      WorkflowDevelopmentParameter(
        id: 'count',
        field: WorkflowOutputField(
          id: 'count',
          name: 'count',
          type: WorkflowOutputType.integer,
        ),
        source: WorkflowDevelopmentParameterSource.manual,
        value: '2',
      ),
      WorkflowDevelopmentParameter(
        id: 'payload',
        field: WorkflowOutputField(
          id: 'payload',
          name: 'payload',
          type: WorkflowOutputType.object,
        ),
        source: WorkflowDevelopmentParameterSource.manual,
        value: '{"items":["a","b"]}',
      ),
      WorkflowDevelopmentParameter(
        id: 'summary',
        field: WorkflowOutputField(id: 'summary', name: 'summary'),
        source: WorkflowDevelopmentParameterSource.manual,
        value: '共 {{count}} 项：{{payload.items}}',
      ),
    ];

    expect(
      resolveWorkflowDevelopmentParameterValues(parameters),
      <String, Object?>{
        'count': 2,
        'payload': <String, Object?>{
          'items': <Object?>['a', 'b'],
        },
        'summary': '共 2 项：["a","b"]',
      },
    );
  });

  test('拒绝临时参数循环引用和不可用引用', () {
    const cyclic = <WorkflowDevelopmentParameter>[
      WorkflowDevelopmentParameter(
        id: 'first',
        field: WorkflowOutputField(id: 'first', name: 'first'),
        source: WorkflowDevelopmentParameterSource.manual,
        value: '{{second}}',
      ),
      WorkflowDevelopmentParameter(
        id: 'second',
        field: WorkflowOutputField(id: 'second', name: 'second'),
        source: WorkflowDevelopmentParameterSource.manual,
        value: '{{first}}',
      ),
    ];
    const missing = <WorkflowDevelopmentParameter>[
      WorkflowDevelopmentParameter(
        id: 'target',
        field: WorkflowOutputField(id: 'target', name: 'target'),
        source: WorkflowDevelopmentParameterSource.manual,
        value: '{{deleted}}',
      ),
    ];

    expect(
      () => resolveWorkflowDevelopmentParameterValues(cyclic),
      throwsA(
        isA<WorkflowNodeExecutionException>().having(
          (error) => error.message,
          'message',
          contains('循环引用'),
        ),
      ),
    );
    expect(
      () => resolveWorkflowDevelopmentParameterValues(missing),
      throwsA(
        isA<WorkflowNodeExecutionException>().having(
          (error) => error.message,
          'message',
          contains('尚未赋值或不可用'),
        ),
      ),
    );
  });
}

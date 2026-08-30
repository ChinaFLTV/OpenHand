import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/workflows/model/workflow_definition.dart';

void main() {
  test('删除上游连线后拒绝保存失效参数引用', () {
    final nodes = <WorkflowNode>[
      _node('start', WorkflowNodeKind.start),
      _node(
        'source',
        WorkflowNodeKind.parameterAssignment,
        settings: _outputFields('result'),
      ),
      _node(
        'end',
        WorkflowNodeKind.end,
        settings: _outputFields('news', defaultValue: '{{result}}'),
      ),
    ];
    const connected = <WorkflowConnection>[
      WorkflowConnection(
        id: 'start-source',
        sourceNodeId: 'start',
        targetNodeId: 'source',
      ),
      WorkflowConnection(
        id: 'source-end',
        sourceNodeId: 'source',
        targetNodeId: 'end',
      ),
    ];
    const disconnected = <WorkflowConnection>[
      WorkflowConnection(
        id: 'start-source',
        sourceNodeId: 'start',
        targetNodeId: 'source',
      ),
      WorkflowConnection(
        id: 'start-end',
        sourceNodeId: 'start',
        targetNodeId: 'end',
      ),
    ];

    expect(validateWorkflowParameterReferences(nodes, connected), isNull);
    final error = validateWorkflowParameterReferences(nodes, disconnected);
    expect(error, contains('参数“result”'));
    expect(error, contains('无法推进到当前节点'));
    expect(error, contains('恢复有效连线'));
  });

  test('仅在部分分支生成的参数不能被汇合节点引用', () {
    final nodes = <WorkflowNode>[
      _node('start', WorkflowNodeKind.start),
      _node(
        'source',
        WorkflowNodeKind.parameterAssignment,
        settings: _outputFields('result'),
      ),
      _node('other', WorkflowNodeKind.llm),
      _node(
        'end',
        WorkflowNodeKind.end,
        settings: _outputFields('news', defaultValue: '{{result}}'),
      ),
    ];
    const connections = <WorkflowConnection>[
      WorkflowConnection(
        id: 'start-source',
        sourceNodeId: 'start',
        targetNodeId: 'source',
      ),
      WorkflowConnection(
        id: 'start-other',
        sourceNodeId: 'start',
        targetNodeId: 'other',
      ),
      WorkflowConnection(
        id: 'source-end',
        sourceNodeId: 'source',
        targetNodeId: 'end',
      ),
      WorkflowConnection(
        id: 'other-end',
        sourceNodeId: 'other',
        targetNodeId: 'end',
      ),
    ];

    final error = validateWorkflowParameterReferences(nodes, connections);

    expect(error, contains('不是当前节点的必经上游'));
    expect(error, contains('每个分支提供该参数'));
  });

  test('校验提示词和输出配置中的不存在引用', () {
    final nodes = <WorkflowNode>[
      _node(
        'start',
        WorkflowNodeKind.start,
        settings: _inputFields('question'),
      ),
      _node(
        'llm',
        WorkflowNodeKind.llm,
        settings: <String, Object?>{
          WorkflowSettingKeys.prompt: '请回答 {{deleted_parameter}}',
        },
      ),
      _node('end', WorkflowNodeKind.end),
    ];
    const connections = <WorkflowConnection>[
      WorkflowConnection(
        id: 'start-llm',
        sourceNodeId: 'start',
        targetNodeId: 'llm',
      ),
      WorkflowConnection(
        id: 'llm-end',
        sourceNodeId: 'llm',
        targetNodeId: 'end',
      ),
    ];

    final error = validateWorkflowParameterReferences(nodes, connections);

    expect(error, contains('提示词'));
    expect(error, contains('不存在的参数“deleted_parameter”'));
    expect(error, contains('必经上游节点添加该参数'));
  });
}

WorkflowNode _node(
  String id,
  WorkflowNodeKind kind, {
  Map<String, Object?> settings = const <String, Object?>{},
}) =>
    WorkflowNode(id: id, kind: kind, title: id, x: 0, y: 0, settings: settings);

Map<String, Object?> _inputFields(String name) => <String, Object?>{
  WorkflowSettingKeys.inputFields: <Object?>[
    <String, Object?>{'id': '$name-input', 'name': name},
  ],
};

Map<String, Object?> _outputFields(String name, {String defaultValue = ''}) =>
    <String, Object?>{
      WorkflowSettingKeys.outputFields: <Object?>[
        <String, Object?>{
          'id': '$name-output',
          'name': name,
          if (defaultValue.isNotEmpty) ...<String, Object?>{
            'default_value': defaultValue,
            'value_source': WorkflowValueSource.variable.storageValue,
          },
        },
      ],
    };

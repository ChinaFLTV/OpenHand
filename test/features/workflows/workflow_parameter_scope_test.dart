import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_template_repository.dart';
import 'package:openhand/features/workflows/model/workflow_definition.dart';
import 'package:openhand/features/workflows/service/workflow_code_executor.dart';
import 'package:openhand/features/workflows/service/workflow_node_executor.dart';

void main() {
  group('工作流参数作用域', () {
    test('禁止跨节点及同节点的输入输出参数重名', () {
      final nodes = <WorkflowNode>[
        _node(
          id: 'code-1',
          title: '代码一',
          kind: WorkflowNodeKind.codeExecution,
          settings: <String, Object?>{
            WorkflowSettingKeys.codeInputFields: <Object?>[
              _field('input-1', 'shared_name').toJson(),
            ],
            WorkflowSettingKeys.outputFields: <Object?>[
              _field('output-1', 'own_name').toJson(),
            ],
          },
        ),
        _node(
          id: 'code-2',
          title: '代码二',
          kind: WorkflowNodeKind.codeExecution,
          settings: <String, Object?>{
            WorkflowSettingKeys.codeInputFields: <Object?>[
              _field('input-2', 'own_name').toJson(),
            ],
            WorkflowSettingKeys.outputFields: <Object?>[
              _field('output-2', 'shared_name').toJson(),
            ],
          },
        ),
      ];

      expect(validateWorkflowParameterNames(nodes), contains('参数名称“own_name”'));
      expect(
        validateWorkflowParameterNames(<WorkflowNode>[
          _node(
            id: 'code-3',
            title: '代码三',
            kind: WorkflowNodeKind.codeExecution,
            settings: <String, Object?>{
              WorkflowSettingKeys.codeInputFields: <Object?>[
                _field('input-3', 'duplicate').toJson(),
              ],
              WorkflowSettingKeys.outputFields: <Object?>[
                _field('output-3', 'duplicate').toJson(),
              ],
            },
          ),
        ]),
        contains('参数名称“duplicate”'),
      );
    });

    test('固定系统输出会自动分配全局唯一名称', () {
      final nodes = normalizeWorkflowSystemOutputNames(<WorkflowNode>[
        _node(id: 'llm-1', title: 'LLM 一', kind: WorkflowNodeKind.llm),
        _node(id: 'llm-2', title: 'LLM 二', kind: WorkflowNodeKind.llm),
        _node(id: 'http-1', title: 'HTTP', kind: WorkflowNodeKind.httpRequest),
      ]);

      final names = nodes
          .expand((node) => node.declaredParameterFields())
          .map((field) => field.name)
          .toList(growable: false);
      expect(names.toSet(), hasLength(names.length));
      expect(nodes[0].systemOutputName(workflowLlmTextOutputName), 'text');
      expect(nodes[1].systemOutputName(workflowLlmTextOutputName), 'text_2');
      expect(validateWorkflowParameterNames(nodes), isNull);
    });

    test('代码节点会发布实际解析后的输入参数', () async {
      final python = _findPython();
      if (python == null) return;
      final start = _node(
        id: 'start',
        title: '开始',
        kind: WorkflowNodeKind.start,
        settings: <String, Object?>{
          WorkflowSettingKeys.inputFields: <Object?>[
            _field('start-text', 'start_text', required: true).toJson(),
            _field(
              'start-number',
              'start_number',
              type: WorkflowOutputType.integer,
              required: true,
            ).toJson(),
          ],
        },
      );
      final code = _node(
        id: 'code',
        title: '代码执行',
        kind: WorkflowNodeKind.codeExecution,
        settings: <String, Object?>{
          WorkflowSettingKeys.codeLanguage:
              WorkflowCodeLanguage.python3.storageValue,
          WorkflowSettingKeys.code:
              '''def main(literal_arg: str, default_arg: str, calculated_arg: int):
    return {"code_result": f"{literal_arg}|{default_arg}|{calculated_arg}"}''',
          WorkflowSettingKeys.codeInputFields: <Object?>[
            _field('literal', 'literal_arg', value: '{{start_text}}!').toJson(),
            _field('default', 'default_arg', defaultValue: 'fallback').toJson(),
            _field(
              'calculated',
              'calculated_arg',
              type: WorkflowOutputType.integer,
              value: '{{start_number}} + 2',
              valueMode: WorkflowValueMode.pythonExpression,
            ).toJson(),
          ],
          WorkflowSettingKeys.outputFields: <Object?>[
            _field('code-result', 'code_result').toJson(),
          ],
          WorkflowSettingKeys.errorStrategy:
              WorkflowErrorStrategy.terminate.storageValue,
        },
      );
      final end = _node(
        id: 'end',
        title: '结束',
        kind: WorkflowNodeKind.end,
        settings: <String, Object?>{
          WorkflowSettingKeys.outputFields: <Object?>[
            _field(
              'final',
              'final_value',
              value:
                  '{{literal_arg}}|{{default_arg}}|{{calculated_arg}}|{{code_result}}',
            ).toJson(),
          ],
        },
      );
      final executor = WorkflowNodeExecutor();
      addTearDown(executor.dispose);

      final result = await executor.executeWorkflow(
        nodes: <WorkflowNode>[start, code, end],
        connections: const <WorkflowConnection>[
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
        ],
        inputs: const <String, Object?>{
          'start_text': 'hello',
          'start_number': 3,
        },
        resources: WorkflowExecutionResources(
          models: const [],
          templateRepository: AiPromptTemplateRepository(
            loader: (_) async => '',
          ),
          codeRuntimes: <WorkflowCodeLanguage, WorkflowCodeRuntime>{
            WorkflowCodeLanguage.python3: WorkflowCodeRuntime(
              language: WorkflowCodeLanguage.python3,
              executable: python,
            ),
          },
        ),
      );

      expect(result.variables['literal_arg'], 'hello!');
      expect(result.variables['default_arg'], 'fallback');
      expect(result.variables['calculated_arg'], 5);
      expect(result.variables['code_result'], 'hello!|fallback|5');
      expect(result.output, const <String, Object?>{
        'final_value': 'hello!|fallback|5|hello!|fallback|5',
      });
    });
  });
}

WorkflowNode _node({
  required String id,
  required String title,
  required WorkflowNodeKind kind,
  Map<String, Object?> settings = const <String, Object?>{},
}) {
  return WorkflowNode(
    id: id,
    title: title,
    kind: kind,
    x: 0,
    y: 0,
    settings: settings,
  );
}

WorkflowOutputField _field(
  String id,
  String name, {
  WorkflowOutputType type = WorkflowOutputType.string,
  bool required = false,
  String value = '',
  WorkflowValueMode valueMode = WorkflowValueMode.literal,
  String defaultValue = '',
}) {
  return WorkflowOutputField(
    id: id,
    name: name,
    type: type,
    required: required,
    value: value,
    valueMode: valueMode,
    defaultValue: defaultValue,
  );
}

String? _findPython() {
  final command = Platform.isWindows ? 'where.exe' : 'which';
  final result = Process.runSync(command, const <String>['python3']);
  if (result.exitCode != 0) return null;
  final executable = '${result.stdout}'.trim().split(RegExp(r'[\r\n]+')).first;
  return executable.isEmpty ? null : executable;
}

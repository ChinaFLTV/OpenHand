import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_template_repository.dart';
import 'package:openhand/features/workflows/model/workflow_definition.dart';
import 'package:openhand/features/workflows/service/workflow_node_executor.dart';

void main() {
  test('取消令牌会阻止节点开始执行', () async {
    final cancellation = WorkflowExecutionCancellationToken()..cancel();
    final executor = WorkflowNodeExecutor();
    addTearDown(executor.dispose);

    await expectLater(
      executor.execute(
        node: const WorkflowNode(
          id: 'condition',
          kind: WorkflowNodeKind.condition,
          title: '条件判断',
          x: 0,
          y: 0,
        ),
        resources: WorkflowExecutionResources(
          models: const [],
          templateRepository: AiPromptTemplateRepository(
            loader: (_) async => '',
          ),
          cancellation: cancellation,
        ),
      ),
      throwsA(isA<WorkflowNodeExecutionCancelledException>()),
    );
  });
}

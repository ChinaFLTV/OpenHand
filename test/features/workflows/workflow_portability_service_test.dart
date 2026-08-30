import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/workflows/model/workflow_definition.dart';
import 'package:openhand/features/workflows/service/workflow_portability_service.dart';

final _workflow = WorkflowDefinition(
  id: 'workflow-special',
  name: '新闻：中文 / 特殊字符',
  createdAt: DateTime.utc(2026, 8, 30, 10),
  updatedAt: DateTime.utc(2026, 8, 30, 11),
  nodes: const <WorkflowNode>[
    WorkflowNode(
      id: 'start',
      kind: WorkflowNodeKind.start,
      title: '开始',
      x: 20,
      y: 40,
      settings: <String, Object?>{'description': '第一行\n第二行: value'},
    ),
    WorkflowNode(
      id: 'end',
      kind: WorkflowNodeKind.end,
      title: '结束',
      x: 420,
      y: 40,
    ),
  ],
  connections: const <WorkflowConnection>[
    WorkflowConnection(
      id: 'edge-1',
      sourceNodeId: 'start',
      targetNodeId: 'end',
    ),
  ],
  annotations: const <WorkflowAnnotation>[
    WorkflowAnnotation(
      id: 'note-1',
      text: '先审核，再发布。',
      x: 180,
      y: 240,
      width: 300,
      height: 160,
      theme: WorkflowAnnotationTheme.green,
      fontSize: 22,
      bold: true,
    ),
  ],
);

void main() {
  test('YAML 导出导入完整保留工作流结构和特殊文本', () {
    final encoded = encodeWorkflowYaml(_workflow);
    final decoded = decodeWorkflowYaml(encoded);

    expect(encoded, startsWith('format: openhand-workflow'));
    expect(decoded.toJson(), _workflow.toJson());
    expect(
      workflowExportFileName(_workflow, WorkflowExportFormat.yaml),
      '新闻：中文 _ 特殊字符.yaml',
    );
  });

  test('YAML 隔离区解析只传递字符串并保留工作流结构', () async {
    final decoded = await decodeWorkflowYamlInIsolate(
      encodeWorkflowYaml(_workflow),
    );

    expect(decoded.toJson(), _workflow.toJson());
  });

  test('YAML 导入拒绝空内容、未知格式和超量画布元素', () {
    expect(
      () => decodeWorkflowYaml(''),
      throwsA(
        isA<WorkflowPortabilityException>().having(
          (error) => error.message,
          'message',
          contains('内容为空'),
        ),
      ),
    );
    expect(
      () => decodeWorkflowYaml('format: dify\nversion: 1\nworkflow: {}'),
      throwsA(
        isA<WorkflowPortabilityException>().having(
          (error) => error.message,
          'message',
          contains('配置格式无效'),
        ),
      ),
    );
    final oversized = jsonEncode(<String, Object?>{
      'format': 'openhand-workflow',
      'version': 1,
      'workflow': <String, Object?>{
        'nodes': List<Object?>.filled(1001, const <String, Object?>{}),
        'connections': const <Object?>[],
      },
    });
    expect(
      () => decodeWorkflowYaml(oversized),
      throwsA(
        isA<WorkflowPortabilityException>().having(
          (error) => error.message,
          'message',
          contains('节点数量超过'),
        ),
      ),
    );
    final oversizedAnnotations = jsonEncode(<String, Object?>{
      'format': 'openhand-workflow',
      'version': 1,
      'workflow': <String, Object?>{
        'nodes': const <Object?>[],
        'connections': const <Object?>[],
        'annotations': List<Object?>.filled(501, const <String, Object?>{}),
      },
    });
    expect(
      () => decodeWorkflowYaml(oversizedAnnotations),
      throwsA(
        isA<WorkflowPortabilityException>().having(
          (error) => error.message,
          'message',
          contains('注释数量超过'),
        ),
      ),
    );
    final invalidAnnotations = jsonEncode(<String, Object?>{
      'format': 'openhand-workflow',
      'version': 1,
      'workflow': <String, Object?>{
        'id': 'invalid-annotations',
        'name': '无效注释',
        'created_at': '2026-08-30T00:00:00Z',
        'updated_at': '2026-08-30T00:00:00Z',
        'nodes': const <Object?>[],
        'connections': const <Object?>[],
        'annotations': const <String, Object?>{},
      },
    });
    expect(
      () => decodeWorkflowYaml(invalidAnnotations),
      throwsA(
        isA<WorkflowPortabilityException>().having(
          (error) => error.message,
          'message',
          contains('注释列表格式无效'),
        ),
      ),
    );
  });

  testWidgets('四种导出格式均生成有效文件内容', (tester) async {
    final artifacts = await tester.runAsync(() async {
      final yaml = await buildWorkflowExportArtifact(
        _workflow,
        WorkflowExportFormat.yaml,
      );
      final png = await buildWorkflowExportArtifact(
        _workflow,
        WorkflowExportFormat.png,
      );
      final jpeg = await buildWorkflowExportArtifact(
        _workflow,
        WorkflowExportFormat.jpeg,
      );
      final svg = await buildWorkflowExportArtifact(
        _workflow,
        WorkflowExportFormat.svg,
      );
      return (yaml: yaml, png: png, jpeg: jpeg, svg: svg);
    });
    final (:yaml, :png, :jpeg, :svg) = artifacts!;

    expect(utf8.decode(yaml.bytes), contains('openhand-workflow'));
    expect(png.bytes.take(8), <int>[137, 80, 78, 71, 13, 10, 26, 10]);
    expect(jpeg.bytes.take(2), <int>[255, 216]);
    expect(utf8.decode(svg.bytes), contains('<svg'));
    expect(utf8.decode(svg.bytes), contains('先审核，再发布。'));
    expect(svg.width, greaterThan(0));
    expect(svg.height, greaterThan(0));
  });
}

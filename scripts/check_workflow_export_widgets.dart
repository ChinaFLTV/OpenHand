import 'dart:io';

import 'support/flutter_widget_check.dart';

Future<void> main() => runFlutterWidgetCheck(
  root: File.fromUri(Platform.script).parent.parent,
  name: 'workflow_export',
  source: _checks,
);

const _checks = '''
import 'dart:convert';
import 'dart:isolate';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:openhand/shared/db/atomic_file_operations.dart';
import 'package:openhand/features/workflows/widgets/workflow_export_progress_dialog.dart';
import 'package:openhand/features/workflows/service/workflow_portability_service.dart';
import 'package:openhand/features/workflows/model/workflow_definition.dart';

class _SlowWorkflow extends WorkflowDefinition {
  _SlowWorkflow() : super(id: '慢任务', name: '超时检查',
    createdAt: DateTime.utc(2026), updatedAt: DateTime.utc(2026));
  @override
  Map<String, Object?> toJson() {
    sleep(const Duration(seconds: 45));
    return super.toJson();
  }
}

void main() {
  test('后台任务超时后终止并返回可见错误', () async {
    await expectLater(buildWorkflowExportArtifact(_SlowWorkflow(), WorkflowExportFormat.yaml),
      throwsA(isA<WorkflowPortabilityException>().having((error) => error.message, '错误提示', contains('超时'))));
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('循环引用与过大配置失败，不会卡住后台任务', () async {
    final settings = <String, Object?>{};
    settings['循环'] = settings;
    final base = WorkflowDefinition(id: '异常', name: '异常配置',
      createdAt: DateTime.utc(2026), updatedAt: DateTime.utc(2026));
    for (final invalid in [settings, {'超大文本': '文' * maxWorkflowEncodedBytes}]) {
      final workflow = base.copyWith(nodes: [WorkflowNode(id: '节点', kind: WorkflowNodeKind.llm,
        title: '节点', x: 0, y: 0, settings: invalid)]);
      await expectLater(buildWorkflowExportArtifact(workflow, WorkflowExportFormat.yaml).timeout(const Duration(seconds: 10)),
        throwsA(isA<WorkflowPortabilityException>()));
    }
  });
  testWidgets('导出弹窗完成真实后台编码后进入成功状态', (tester) async {
    final directory = Directory.systemTemp.createTempSync('工作流导出检查');
    addTearDown(() => directory.deleteSync(recursive: true));
    final output = File('\${directory.path}/测试.yaml');
    final workflow = WorkflowDefinition(id: '导出', name: '流程', createdAt: DateTime.utc(2026), updatedAt: DateTime.utc(2026));
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => TextButton(
      onPressed: () => showWorkflowExportProgressDialog(context: context, formatLabel: 'YAML',
        task: (progress) async {
          final artifact = await buildWorkflowExportArtifact(workflow, WorkflowExportFormat.yaml, onProgress: progress);
          expect(artifact.bytes, isNotEmpty);
          await writeBytesFileAtomically(output, artifact.bytes);
          return output.path;
        }), child: const Text('导出')))));
    await tester.runAsync(() async {
      await tester.tap(find.text('导出'));
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        if (find.text('导出完成').evaluate().isNotEmpty) break;
      }
    });
    expect(find.text('导出完成'), findsOneWidget);
    expect(decodeWorkflowYaml(output.readAsStringSync()).id, workflow.id);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  test('YAML 后台导出不捕获进度回调中的主线程资源', () async {
    final port = ReceivePort();
    addTearDown(port.close);
    final workflow = WorkflowDefinition(id: '导出', name: '测试流程',
      createdAt: DateTime.utc(2026), updatedAt: DateTime.utc(2026),
      nodes: [WorkflowNode(id: '模型', kind: WorkflowNodeKind.llm,
        title: '生成结论', x: 20, y: 30,
        settings: {'prompt': '多行提示词\\n中文与符号：[] {}', 'array': [1, true, null], 'object': {'内容': '测试'}})],
    );
    final progress = <double>[];
    final artifact = await buildWorkflowExportArtifact(workflow, WorkflowExportFormat.yaml,
      onProgress: (value, message) { progress.add(value); port.sendPort.send(message); },
    ).timeout(const Duration(seconds: 10));
    expect(decodeWorkflowYaml(utf8.decode(artifact.bytes)).toJson(), WorkflowDefinition.fromJson(workflow.toJson()).toJson());
    expect(progress, [0.12, 0.62, 0.84]);
  });
}
''';

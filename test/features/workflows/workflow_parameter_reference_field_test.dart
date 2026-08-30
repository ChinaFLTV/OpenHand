import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/workflows/model/workflow_definition.dart';
import 'package:openhand/features/workflows/widgets/workflow_parameter_reference_field.dart';

const _references = <WorkflowParameterReference>[
  WorkflowParameterReference(
    nodeId: 'upstream-node',
    nodeTitle: '上游节点',
    field: WorkflowOutputField(
      id: 'output-field',
      name: 'result',
      description: '执行结果',
    ),
  ),
];

Future<void> _pumpReferenceField(
  WidgetTester tester, {
  GlobalKey<_ReferenceFieldHostState>? key,
  bool disableAnimations = true,
}) {
  return tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(disableAnimations: disableAnimations),
        child: child!,
      ),
      home: Scaffold(body: _ReferenceFieldHost(key: key)),
    ),
  );
}

void main() {
  testWidgets('输入斜杠并同步回写时安全显示参数菜单', (tester) async {
    await _pumpReferenceField(tester);

    await tester.enterText(find.byType(TextField).first, '/');
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('上游节点'), findsOneWidget);
    expect(find.text('result'), findsOneWidget);
  });

  testWidgets('参数菜单可通过 ESC 平滑关闭并归还输入焦点', (tester) async {
    await _pumpReferenceField(tester, disableAnimations: false);

    await tester.enterText(find.byType(TextField).first, '/');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('上游节点'), findsNothing);
    expect(
      Focus.of(tester.element(find.byType(TextField).first)).hasFocus,
      isTrue,
    );
  });

  testWidgets('菜单打开时参数失效可安全关闭过期浮层', (tester) async {
    final hostKey = GlobalKey<_ReferenceFieldHostState>();
    await _pumpReferenceField(tester, key: hostKey);

    await tester.enterText(find.byType(TextField).first, '/');
    await tester.pump();
    expect(find.text('上游节点'), findsOneWidget);

    hostKey.currentState!.clearReferences();
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('上游节点'), findsNothing);
  });
}

class _ReferenceFieldHost extends StatefulWidget {
  const _ReferenceFieldHost({super.key});

  @override
  State<_ReferenceFieldHost> createState() => _ReferenceFieldHostState();
}

class _ReferenceFieldHostState extends State<_ReferenceFieldHost> {
  String _value = '';
  List<WorkflowParameterReference> _availableReferences = _references;

  void clearReferences() {
    setState(() {
      _availableReferences = const <WorkflowParameterReference>[];
    });
  }

  @override
  Widget build(BuildContext context) {
    return WorkflowParameterReferenceField(
      value: _value,
      references: _availableReferences,
      decoration: const InputDecoration(labelText: '参数值'),
      onChanged: (next) => setState(() => _value = next),
    );
  }
}

import 'dart:io';

import 'support/flutter_widget_check.dart';

Future<void> main() => runFlutterWidgetCheck(
  root: File.fromUri(Platform.script).parent.parent,
  name: 'tooltip_handoff',
  source: r'''
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/ui/openhand_ops_charts.dart';

Widget table(String prefix) => SizedBox(width: 440, child: OpenHandOperationalRankTable(
  headers: const ['名称', '镜像'], sortByValue: false, paginate: false, maxBodyHeight: 420,
  rows: [for(var i=0;i<6;i++) OpenHandOperationalRankRow(value:0,
    cells:['$prefix-$i','image-$prefix-$i:latest'],
    cellWidgets:[Text('$prefix-$i',key:ValueKey('$prefix-$i')),null])],
));

Widget app(Widget child, {bool reduced=false}) => MaterialApp(
  builder:(context,child)=>MediaQuery(data:MediaQuery.of(context).copyWith(disableAnimations:reduced),child:child!),
  home:Scaffold(body:child),
);

Finder card() => find.byWidgetPredicate((widget)=>widget.runtimeType.toString()=='_HeatmapHoverCard');
Finder popupText(String value)=>find.descendant(of:card(),matching:find.text(value));

void main() {
  testWidgets('全文浮窗在入场完成后下一帧切换内容，覆盖区域仍可命中底层单元格', (tester) async {
    for(final reduced in [false,true]) {
      await tester.pumpWidget(app(Center(child:table('first')),reduced:reduced));
      await tester.pumpAndSettle();
      final mouse=await tester.createGesture(kind:ui.PointerDeviceKind.mouse);
      await mouse.addPointer(location:Offset.zero);
      await mouse.moveTo(tester.getCenter(find.byKey(const ValueKey('first-5'))));
      await tester.pumpAndSettle();
      expect(popupText('first-5'),findsOneWidget);
      final popup=tester.getRect(card());
      final covered=[for(var i=0;i<5;i++) if(popup.contains(tester.getCenter(find.byKey(ValueKey('first-$i'))))) i];
      expect(covered,isNotEmpty,reason:'验证浮窗遮盖单元格的真实鼠标路径');
      final target=covered.last;
      final label=find.byKey(ValueKey('first-$target'));
      expect(label.hitTestable(),findsOneWidget);
      await mouse.moveTo(tester.getCenter(label));await tester.pump();
      expect(popupText('first-$target'),findsOneWidget);
      expect(popupText('first-5'),findsNothing);expect(card(),findsOneWidget);
      for(final i in [0,3,1,4,2]) {
        await mouse.moveTo(tester.getCenter(find.byKey(ValueKey('first-$i'))));await tester.pump();
        expect(popupText('first-$i'),findsOneWidget);expect(card(),findsOneWidget);
      }
      await tester.pump(const Duration(milliseconds:500));expect(popupText('first-2'),findsOneWidget);
      await mouse.moveTo(Offset.zero);await tester.pumpAndSettle();expect(card(),findsNothing);
      await mouse.removePointer();await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(),isNull);
    }
  });

  testWidgets('跨表格与公共触发器切换取消旧提示，迟到回调不会关闭当前提示', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000,800));
    await tester.pumpWidget(app(Column(children:[
      Row(crossAxisAlignment:CrossAxisAlignment.start,children:[table('left'),table('right')]),
      OpenHandChartTooltipTrigger(accent:Colors.green,
        tooltip:const OpenHandChartTooltip(title:'第三个提示',summary:'当前完整内容'),
        child:const SizedBox(width:200,height:60,child:Text('新目标',key:ValueKey('new-target')))),
    ])));
    await tester.pumpAndSettle();
    final mouse=await tester.createGesture(kind:ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location:Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byKey(const ValueKey('left-2'))));await tester.pumpAndSettle();
    expect(popupText('left-2'),findsOneWidget);
    await mouse.moveTo(tester.getCenter(find.byKey(const ValueKey('right-2'))));await tester.pump();
    expect(popupText('right-2'),findsOneWidget);expect(popupText('left-2'),findsNothing);expect(card(),findsOneWidget);
    await mouse.moveTo(tester.getCenter(find.byKey(const ValueKey('new-target'))));await tester.pump();
    expect(popupText('当前完整内容'),findsOneWidget);expect(popupText('right-2'),findsNothing);
    await tester.pump(const Duration(seconds:1));expect(card(),findsOneWidget);
    await mouse.moveTo(tester.getCenter(find.byKey(const ValueKey('left-0'))));await tester.pump();
    expect(popupText('left-0'),findsOneWidget);expect(card(),findsOneWidget);
    await tester.pumpWidget(const SizedBox());await tester.pump(const Duration(seconds:1));
    expect(card(),findsNothing);expect(tester.takeException(),isNull);
    await mouse.removePointer();await tester.binding.setSurfaceSize(null);
  });

  testWidgets('快速扫过未显示目标后卸载不会遗留计时器或过期浮窗', (tester) async {
    await tester.pumpWidget(app(Center(child:table('pending'))));await tester.pumpAndSettle();
    final mouse=await tester.createGesture(kind:ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location:Offset.zero);
    for(final i in [0,1,2,3]) {
      await mouse.moveTo(tester.getCenter(find.byKey(ValueKey('pending-$i'))));
      await tester.pump(const Duration(milliseconds:10));
    }
    await tester.pumpWidget(const SizedBox());await tester.pump(const Duration(seconds:1));
    expect(card(),findsNothing);expect(tester.takeException(),isNull);await mouse.removePointer();
  });
}
''',
);

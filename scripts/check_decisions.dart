import 'dart:io';
import 'support/flutter_widget_check.dart';

Future<void> main() => runFlutterWidgetCheck(
  root: File.fromUri(Platform.script).parent.parent,
  name: 'decisions',
  source: _checks,
);

const _checks = '''
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openhand/features/ai/model/ai_api_family.dart';
import 'package:openhand/features/ai/model/ai_endpoint_override.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/service/chat/ai_chat_service.dart';
import 'package:openhand/features/ai/service/operations/ai_decisions_service.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/runtime/ai_endpoint_router.dart';
import 'package:openhand/features/ai/service/model_registry/ai_model_scanner.dart';
import 'package:openhand/shared/util/decision_payload.dart';
import 'package:openhand/shared/ui/decision_card.dart';
import 'package:openhand/shared/ui/decision_request_dialog.dart';

AiModelConfig config({String base = 'https://api.typesafe.ai/v1', String id = 'jev-latest'}) => AiModelConfig(id: '测试', baseUrl: base, authScheme: AiAuthScheme.bearer, token: '测试令牌', modelId: id, protocolType: AiProtocolType.openai);
const question = {'判断': {'type': 'noul', 'instructions': '成立吗？'}};
const response = {'model': 'jev-1.13.0', 'answers': {'判断': {'type': 'noul', 'noul': 0.8}}, 'usage': {'input_tokens': 12, 'output_tokens': 3}};
List<AiChatTurn> turns() => [const AiChatTurn(role: AiChatRole.system, content: '不得发送的系统提示词'), AiChatTurn(role: AiChatRole.user, content: DecisionPayload.encode(DecisionPayload.requestLanguage, {'state': '待判断内容', 'questions': question}))];

void main() {
  test('三类默认问题按类型更新，自定义问题保留', () {
    expect(DecisionPayload.defaultQuestions.values.toSet(), hasLength(3));
    for (final type in DecisionPayload.defaultQuestions.keys) {
      final expected = DecisionPayload.defaultQuestions[type];
      for (final current in ['', '  ', ...DecisionPayload.defaultQuestions.values]) {
        expect(DecisionPayload.questionForType(type, current: current), expected);
      }
      expect(DecisionPayload.questionForType(type, current: '  该请求是否需要人工处理？  '), '  该请求是否需要人工处理？  ');
    }
  });
  testWidgets('决策弹窗切换类型同步默认问题且不覆盖自定义内容', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => TextButton(
      onPressed: () => showDecisionRequestDialog(context, '待评估内容'), child: const Text('打开'),
    ))));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    final questionField = find.byWidgetPredicate((widget) => widget is TextField && widget.decoration?.labelText == '需要模型回答的问题');
    for (final entry in {'choice': '选择', 'score': '评分', 'noul': '判断'}.entries) {
      await tester.tap(find.widgetWithText(ChoiceChip, entry.value));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(questionField).controller!.text, DecisionPayload.defaultQuestions[entry.key]);
    }
    await tester.enterText(questionField, '哪个团队负责售后？');
    await tester.tap(find.widgetWithText(ChoiceChip, '选择'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(questionField).controller!.text, '哪个团队负责售后？');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  });
  test('原生、网关与完整接口地址正确归一化', () {
    const router = AiEndpointRouter();
    for (final base in ['https://api.typesafe.ai', 'https://api.typesafe.ai/v1', 'https://api.typesafe.ai/v1/systemone']) {
      expect(router.resolve(config(base: base), AiApiFamily.decisions).url, 'https://api.typesafe.ai/v1/systemone');
    }
    for (final base in ['https://openrouter.ai', 'https://openrouter.ai/api', 'https://openrouter.ai/api/v1', 'https://openrouter.ai/api/alpha/decisions']) {
      expect(router.resolve(config(base: base, id: 'typesafe/jev-1.13'), AiApiFamily.decisions).url, 'https://openrouter.ai/api/alpha/decisions');
    }
    final custom = config().copyWith(endpointOverrides: {AiApiFamily.decisions: const AiEndpointOverride(url: 'https://relay.example/evaluate')});
    expect(router.resolve(custom, AiApiFamily.decisions).url, 'https://relay.example/evaluate');
  });
  test('请求不发送聊天字段，答案保留结构和用量', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      expect(request.url.path, '/v1/systemone');
      expect(jsonDecode(request.body), {'model': 'jev-latest', 'state': '待判断内容', 'questions': question});
      expect(request.headers['authorization'], 'Bearer 测试令牌');
      return http.Response(jsonEncode(response), 200, headers: {'content-type': 'application/json; charset=utf-8'});
    });
    final service = AiChatService(client: client);
    addTearDown(service.dispose);
    addTearDown(client.close);
    final result = await service.sendMessage(model: config(), messages: turns());
    expect(result.reply, contains('openhand-decision'));
    expect(result.reply, contains('0.8'));
    expect(result.usage, isNotNull);
    expect(calls, 1);
  });
  test('决策流只发送完整结果，错误不回退到聊天接口', () async {
    var status = 200;
    var calls = 0;
    final client = MockClient((request) async { calls++; return http.Response(jsonEncode(status == 200 ? response : {'error': '拒绝访问'}), status, headers: {'content-type': 'application/json; charset=utf-8'}); });
    final service = AiChatService(client: client);
    addTearDown(service.dispose);
    addTearDown(client.close);
    final stream = await service.sendMessageStream(model: config(), messages: turns());
    final events = await stream.events.toList();
    expect(events.where((event) => event.type == AiChatStreamEventType.textDelta).length, 1);
    expect((await stream.result).reply, contains('openhand-decision'));
    status = 429;
    await expectLater(service.sendMessage(model: config(), messages: turns()), throwsA(isA<AiChatException>()));
    expect(calls, 2);
  });
  test('TypeSafe 模型目录解析 name 字段', () async {
    final client = MockClient((_) async => http.Response('{"models":[{"name":"jev-latest"},{"name":"jev-preview"}]}', 200));
    final scanner = AiModelScanner(httpClient: client);
    addTearDown(scanner.dispose);
    addTearDown(client.close);
    expect((await scanner.scan(config())).modelIds, ['jev-latest', 'jev-preview']);
  });
  test('选择与评分保留概率分布，无效结果不能伪装成功', () {
    final questions = {'分类': {'type': 'choice', 'instructions': '归类', 'criteria': {'甲': null, '乙': null}}, '评分': {'type': 'score', 'instructions': '评分', 'criteria': ['低', '高']}};
    final result = DecisionPayload.result({'answers': {'分类': {'type': 'choice', 'choice': '甲', 'probabilities': {'甲': .8, '乙': .2}, 'confidence': .7}, '评分': {'type': 'score', 'score': .4, 'legend': {'0': '低', '1': '高'}, 'probabilities': {'0': .6, '1': .4}, 'confidence': .2}}}, questions);
    expect(result['answers'], isNotEmpty);
    expect(() => DecisionPayload.result({'answers': {'判断': {'type': 'noul', 'noul': 2}}}, question), throwsFormatException);
    expect(() => DecisionPayload.result({'answers': {}}, question), throwsFormatException);
    expect(() => DecisionPayload.request('{"state":"内容","questions":{"问题":{"type":"score","instructions":"评分","criteria":["低"]}}}'), throwsFormatException);
  });
  test('取消等待立即释放结果，迟到响应不再产生输出', () async {
    final pending = Completer<http.Response>();
    final client = MockClient((_) => pending.future);
    final service = AiChatService(client: client);
    addTearDown(service.dispose);
    addTearDown(client.close);
    final stream = await service.sendMessageStream(model: config(), messages: turns());
    final events = stream.events.toList();
    await stream.cancel!();
    expect((await stream.result.timeout(const Duration(seconds: 2))).wasCancelled, isTrue);
    pending.complete(http.Response(jsonEncode(response), 200, headers: {'content-type': 'application/json; charset=utf-8'}));
    expect(await events, isEmpty);
  });
  test('文本分段可作为决策输入', () async {
    final client = MockClient((request) async {
      expect((jsonDecode(request.body) as Map)['state'], '分段文本');
      return http.Response(jsonEncode(response), 200, headers: {'content-type': 'application/json; charset=utf-8'});
    });
    addTearDown(client.close);
    final result = await AiDecisionsService(client).evaluate(model: config(), messages: [const AiChatTurn(role: AiChatRole.user, content: '', parts: [AiChatContentPart.text('分段文本')])], timeout: const Duration(seconds: 1));
    expect(result.reply, contains('openhand-decision'));
  });
  test('超时终止等待且不重复请求', () async {
    final pending = Completer<http.Response>();
    var calls = 0;
    final client = MockClient((_) { calls++; return pending.future; });
    addTearDown(client.close);
    await expectLater(AiDecisionsService(client).evaluate(model: config(), messages: turns(), timeout: const Duration(milliseconds: 20)), throwsA(isA<TimeoutException>()));
    expect(calls, 1);
    pending.complete(http.Response('{}', 200));
  });
  testWidgets('复杂配置重新打开不丢失批量问题与描述', (tester) async {
    final request = {'state': {'内容': '批量'}, 'questions': {'分类': {'type': 'choice', 'instructions': '分类', 'criteria': {'甲': '详细标准', '乙': null}}, '判断': {'type': 'noul', 'instructions': '成立吗？'}}};
    final original = DecisionPayload.encode(DecisionPayload.requestLanguage, request);
    String? updated;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => TextButton(onPressed: () async { updated = await showDecisionRequestDialog(context, original); }, child: const Text('打开')))));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('完整决策配置（JSON）'), findsOneWidget);
    await tester.tap(find.text('应用到草稿'));
    await tester.pumpAndSettle();
    expect(DecisionPayload.request(updated!), request);
  });
  testWidgets('决策卡片窄屏无溢出，弹窗可填写并保留草稿', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? draft;
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: RepaintBoundary(key: key, child: Builder(builder: (context) => ListView(children: [
      OpenHandDecisionCard(data: DecisionPayload.result(Map<String,Object?>.from(response), question)),
      TextButton(onPressed: () async { draft = await showDecisionRequestDialog(context, '一加一等于二'); }, child: const Text('配置')),
    ]))))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('/tmp/openhand-jev-card.png').writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    await tester.tap(find.text('配置'));
    await tester.pumpAndSettle();
    expect(find.text('配置结构化决策'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('应用到草稿'));
    await tester.pumpAndSettle();
    expect(DecisionPayload.request(draft!)['state'], '一加一等于二');
  });
}
''';

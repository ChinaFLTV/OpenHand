import 'dart:io';

import 'support/flutter_widget_check.dart';

Future<void> main() async {
  final root = File.fromUri(Platform.script).parent.parent;
  await runFlutterWidgetCheck(
    root: root,
    name: 'structured_content',
    source: _checks,
  );
}

const _checks = r"""
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/l10n/app_localizations.dart';
import 'package:openhand/shared/ui/openhand_json_tree.dart';
import 'package:openhand/app/theme/openhand_theme.dart';
import 'package:openhand/app/theme/openhand_theme_preset.dart';
import 'package:openhand/shared/util/structured_content.dart';
import 'package:openhand/shared/util/structured_text_format.dart';

const plist = '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>com.apple.ManagedClientAgent.enrollagent</string>
<key>EnablePressuredExit</key><false/>
<key>ProgramArguments</key><array><string>/System/Library/CoreServices/ManagedClient.app/Contents/Resources/ManagedClientAgent</string><string>-j</string></array>
<key>StartInterval</key><integer>7200</integer>
<key>备注</key><string>  空白 &amp; 中文\n保留原文  </string>
</dict></plist>
''';

void main() {
  test('原生配置转换保留字段类型、重复节点、属性、混合文本和安全整数', () {
    final values = parseOpenHandStructuredContent(plist).value as Map;
    expect(values['EnablePressuredExit'],false);
    expect(values['StartInterval'],7200);
    expect(values['ProgramArguments'],isA<List>());
    expect(values['备注'],'  空白 & 中文\n保留原文  ');
    final xml = parseOpenHandStructuredContent('<Task id="1"><Action>A</Action><Action>B</Action><Name> x </Name></Task>').value as Map;
    expect(xml['Task'],{'@id':'1','Action':['A','B'],'Name':' x '});
    expect(parseOpenHandStructuredContent('<p>前<b>中</b>后</p>').value,{'p':{'#content':['前',{'b':'中'},'后']}});
    expect(parseOpenHandStructuredContent('services:\n  app:\n    enabled: true\n    ports: [80, 443]').value,
      {'services':{'app':{'enabled':true,'ports':[80,443]}}});
    expect(parseOpenHandStructuredContent('[Unit]\nDescription=  示例  \n[Service]\nEnvironment=A=1\nEnvironment=B=2').value,
      {'Unit':{'Description':'  示例  '},'Service':{'Environment':['A=1','B=2']}});
    expect(parseOpenHandStructuredContent('[1,2]').language,'json');
    expect(parseOpenHandStructuredContent('[Unit]\ninvalid',language:'ini').value,isNull);
    final huge = '9' * 1000;
    expect((parseOpenHandStructuredContent('<plist><dict><key>编号</key><integer>$huge</integer></dict></plist>').value as Map)['编号'],huge);
  });

  test('损坏、重复、未知和超限内容保留原文，不尝试循环或别名展开', () {
    for (final text in [
      '<plist><dict><key>A</key></dict></plist>',
      '<plist><dict><key>A</key><string>1</string><key>A</key><string>2</string></dict></plist>',
      '<root><child></root>', '{"x":', 'text', '\u0000binary',
      'a: &loop [*loop]', 'a: [1,',
      List.generate(40, (index)=>'${' ' * index}a:').join('\n'),
      'a: ${'[' * 80}${']' * 80}',
      '${'<a>' * 40}${'</a>' * 40}',
      '<a>${'<b/>' * 5000}</a>',
      '{"items":[${List.filled(5000,'0').join(',')}]}'
    ]) {
      expect(parseOpenHandStructuredContent(text).value,isNull,reason:text.substring(0,text.length.clamp(0,60)));
    }
    expect(parseOpenHandStructuredContent('a: ${'x' * kOpenHandNativeContentMaxCharacters}').value,isNull);
    expect(parseOpenHandStructuredContent('{"a":"${'x' * kOpenHandJsonTreeMaxCharacters}"}').value,isNull);
    expect(parseOpenHandStructuredContent('[Unit]\nDescription=示例',language:'systemd').language,'ini');
  });

  test('格式化阶段与阅读视图共用预算，异常内容不展开或递归缩进', () {
    for(final text in ['${'<a>' * 100}${'</a>' * 100}', '<a>${'<b/>' * 5000}</a>', 'a: &loop [*loop]', 'a: ${'[' * 100}${']' * 100}']) {
      final result=formatStructuredTextForDisplay(text);
      expect(result.format,isNull);expect(result.text,text);
    }
    expect(formatStructuredTextForDisplay(plist).format,StructuredTextFormat.xml);
    expect(formatStructuredTextForDisplay('a:\n  b: true').text,contains('"b": true'));
  });

  testWidgets('六语言、明暗主题、窄屏及放大字号共用树，原文切换和复制无损', (tester) async {
    await tester.runAsync(() async {
      for(final entry in {'配置预览字体':Platform.environment['MAINTENANCE_FONT'],'monospace':Platform.environment['MAINTENANCE_TERMINAL_FONT'],'MaterialIcons':Platform.environment['MAINTENANCE_ICONS']}.entries) {
        if(entry.value!=null) await (FontLoader(entry.key)..addFont(File(entry.value!).readAsBytes().then((bytes)=>ByteData.sublistView(bytes)))).load();
      }
    });
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform,(call) async {
      if (call.method=='Clipboard.setData') copied=(call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(()=>tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform,null));
    for (final locale in [const Locale('zh'),const Locale('zh','TW'),const Locale('en'),const Locale('fr'),const Locale('de'),const Locale('ja')]) {
      for (final dark in [false,true]) {
        await tester.binding.setSurfaceSize(const Size(380,800));
        await tester.pumpWidget(MaterialApp(locale:locale,
          localizationsDelegates:AppLocalizations.localizationsDelegates,supportedLocales:AppLocalizations.supportedLocales,
          theme:(dark?OpenHandTheme.dark(OpenHandThemePreset.tundraGreen):OpenHandTheme.light(OpenHandThemePreset.tundraGreen)).copyWith(
            textTheme:(dark?OpenHandTheme.dark(OpenHandThemePreset.tundraGreen):OpenHandTheme.light(OpenHandThemePreset.tundraGreen)).textTheme.apply(fontFamily:Platform.environment['MAINTENANCE_FONT']==null?null:'配置预览字体')),
          home:MediaQuery(data:const MediaQueryData(size:Size(380,800),textScaler:TextScaler.linear(1.5)),
            child:Scaffold(body:SingleChildScrollView(child:RepaintBoundary(key:const ValueKey('预览'),
              child:OpenHandJsonTreeView(text:plist,parseStructuredText:true,bodyMaxHeight:280)))))));
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.code_rounded),findsOneWidget);
        expect(find.byType(SelectableText),findsWidgets);
        await tester.tap(find.byIcon(Icons.copy_rounded));await tester.pumpAndSettle();
        expect(copied,plist);
        await tester.tap(find.byIcon(Icons.code_rounded));await tester.pumpAndSettle();
        final text = tester.widget<SelectableText>(find.byType(SelectableText));
        expect(text.textSpan!.toPlainText(),plist);
        final colors = <Color>{};
        void walk(InlineSpan span) {
          if(span is TextSpan) {if(span.style?.color case final Color color) colors.add(color);for(final child in span.children??<InlineSpan>[]) walk(child);}
        }
        walk(text.textSpan!);expect(colors.length,greaterThan(2));
        if(locale.languageCode=='zh'&&!dark) {
          await tester.runAsync(() async {
            final image=await tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('预览'))).toImage(pixelRatio:1.5);
            final bytes=await image.toByteData(format:ui.ImageByteFormat.png);
            await File('/tmp/openhand-native-source.png').writeAsBytes(bytes!.buffer.asUint8List());image.dispose();
          });
        }
        await tester.tap(find.byIcon(Icons.account_tree_outlined));await tester.pumpAndSettle();
        expect(find.byIcon(Icons.code_rounded),findsOneWidget);
        if(locale.languageCode=='zh'&&!dark) {
          await tester.runAsync(() async {
            final image=await tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('预览'))).toImage(pixelRatio:1.5);
            final bytes=await image.toByteData(format:ui.ImageByteFormat.png);
            await File('/tmp/openhand-native-tree.png').writeAsBytes(bytes!.buffer.asUint8List());image.dispose();
          });
        }
        expect(tester.takeException(),isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('无法高亮时仍可复制，超长预览有界，完整视图保留原文', (tester) async {
    for(final source in ['bad <xml', '配置\n未知语言', 'x' * (kOpenHandNativeContentMaxCharacters+1)]) {
      await tester.pumpWidget(MaterialApp(home:Scaffold(body:SingleChildScrollView(child:OpenHandJsonTreeView(text:source,
        language:'not-a-language',parseStructuredText:true)))));
      await tester.pumpAndSettle();
      final text=tester.widget<SelectableText>(find.byType(SelectableText));
      expect(text.textSpan!.toPlainText(),source.length>kOpenHandNativeContentMaxCharacters?'${source.substring(0,kOpenHandNativeContentMaxCharacters)}\n…':source);
      expect(tester.takeException(),isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
    final unicode='${'x' * (kOpenHandNativeContentMaxCharacters-1)}😀末尾';
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:SingleChildScrollView(child:OpenHandJsonTreeView(text:unicode,parseStructuredText:true)))));
    await tester.pumpAndSettle();
    expect(tester.widget<SelectableText>(find.byType(SelectableText)).textSpan!.toPlainText(),'${'x' * (kOpenHandNativeContentMaxCharacters-1)}\n…');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:OpenHandJsonTreeView(text:plist,parseStructuredText:true))));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.code_rounded));await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.open_in_full_rounded));await tester.pumpAndSettle();
    expect(find.byType(Dialog),findsOneWidget);
    final views=tester.widgetList<OpenHandJsonTreeView>(find.byType(OpenHandJsonTreeView)).toList();
    expect(views.last.enableFullView,isFalse);expect(views.last.showSource,isTrue);expect(views.last.text,plist);
    expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('内容和格式提示更新后重新解析，减少动画设置立即生效', (tester) async {
    Future<void> show(String text, {String? language}) async {
      await tester.pumpWidget(MaterialApp(home:MediaQuery(data:const MediaQueryData(disableAnimations:true),child:Scaffold(
        body:OpenHandJsonTreeView(text:text,language:language,parseStructuredText:true)))));
      await tester.pump();
      expect(find.byType(AnimatedSize),findsNothing);
      expect(tester.takeException(),isNull);
    }
    await show(plist);await show(plist,language:'plaintext');
    expect(find.byIcon(Icons.code_rounded),findsNothing);
    expect(tester.widget<SelectableText>(find.byType(SelectableText)).textSpan!.toPlainText(),plist);
    await show('{"items":[true,null]}');expect(find.byIcon(Icons.code_rounded),findsOneWidget);
    await show('',language:'xml');expect(find.byType(SelectableText),findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
""";

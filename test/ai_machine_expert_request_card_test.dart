import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';

void main() {
  test('parses machine expert request prompt into display card metadata', () {
    final card = AiMachineExpertRequestCard.fromPrompt('''
- 终端应用：【iTerm2 (AppleScript 进程名为 iTerm)】
- 打开的终端位置：【窗口：liguanda@Mac:~，会话：~ (-zsh)】
- AppleScript 精确定位：【window 1 → tab 1 → session 1】
- 需求内容（工作环境是：用户在【终端应用】与【打开的终端位置】输入参数中共同指定的目标终端会话环境）：【检查 CPU 状态
并汇总关键进程】''');

    expect(card, isNotNull);
    expect(card!.terminalApplication, 'iTerm2 (AppleScript 进程名为 iTerm)');
    expect(card.terminalLocation, '窗口：liguanda@Mac:~，会话：~ (-zsh)');
    expect(card.appleScriptTarget, 'window 1 → tab 1 → session 1');
    expect(card.taskRequirement, '检查 CPU 状态\n并汇总关键进程');

    final restored = AiMachineExpertRequestCard.fromMetadata(card.toJson());
    expect(restored?.taskRequirement, card.taskRequirement);
  });

  test('ignores unrelated user prompts', () {
    expect(AiMachineExpertRequestCard.fromPrompt('帮我写一个脚本'), isNull);
    expect(AiMachineExpertRequestCard.fromPrompt('需求内容：【只是普通描述】'), isNull);
  });

  test('parses web reverse request prompt into display card metadata', () {
    final card = AiWebReverseRequestCard.fromPrompt('''
请求模板：
- 目标 URL：【https://docs.yukework.com/doc?fileId=20691029858193998146】
- 逆向目标：【给我看下这个文章的内容】
- 登录态：【无需登录】
- 浏览器：【Google Chrome】
- CDP 端口：【9223】
- AI 侧 CDP MCP：【未启用；如需临时 chrome-devtools-mcp，请先在调试面板手动开启】
- 取证纪律：【先确认 CDP / chrome-devtools / js-reverse MCP 工具名；先 Observe 请求、initiator、脚本；禁止 WebFetch/WebSearch/Bash/curl 直接抓目标源】
- 任务产物：【目标请求、initiator、可疑脚本、关键 hook/断点、入参返回、first divergence、本地复现脚本】
- 验收标准：【可在 curl / Dart / Python 中独立复现，无需浏览器】''');

    expect(card, isNotNull);
    expect(card!.targetUrl, contains('docs.yukework.com'));
    expect(card.reverseTarget, '给我看下这个文章的内容');
    expect(card.browser, 'Google Chrome');
    expect(card.cdpPort, '9223');
    expect(card.deliverables, contains('first divergence'));

    final restored = AiWebReverseRequestCard.fromMetadata(card.toJson());
    expect(restored?.targetUrl, card.targetUrl);
    expect(restored?.acceptanceCriteria, card.acceptanceCriteria);
  });

  test('parses android reverse request prompt into display card metadata', () {
    final card = AiAndroidReverseRequestCard.fromPrompt('''
Android 逆向请求：
- 逆向目标：【看下这个安装包的各个依赖的版本】
- 目标包名：【com.fltv.codaily】
- APK 路径：【/tmp/hehe.apk】
- 设备：【自动选择在线设备】
- 分析模式：【均衡分析】
- 授权范围：【未填写；仅允许非破坏性静态分析，动态动作需再次确认】
- ADB MCP：【未启用；优先用 Bash/ADB 兜底】
- Frida MCP：【未启用；优先用 Bash/Frida CLI 兜底】
- 取证纪律：【先 adb devices 确认设备；域名/URL定位优先静态扫描APK；静态证据已闭环时先交付结论；动态验证需用户批准；同一错误连续≥2轮停下报告】
- 验收标准：【结论有证据路径；若生成脚本/命令，需可在无 IDE 环境下独立运行】''');

    expect(card, isNotNull);
    expect(card!.reverseTarget, '看下这个安装包的各个依赖的版本');
    expect(card.packageName, 'com.fltv.codaily');
    expect(card.apkPath, '/tmp/hehe.apk');
    expect(card.deviceDisplay, '自动选择在线设备');
    expect(card.fridaMcp, contains('Frida CLI'));

    final restored = AiAndroidReverseRequestCard.fromMetadata(card.toJson());
    expect(restored?.packageName, card.packageName);
    expect(restored?.acceptanceCriteria, card.acceptanceCriteria);
  });

  test('keeps android device and device serial fields distinct', () {
    final card = AiAndroidReverseRequestCard.fromPrompt('''
Android 逆向请求：
- 逆向目标：【确认登录接口签名】
- 目标包名：【com.example.demo】
- 设备序列号：【emulator-5554】
- 分析模式：【动态验证优先】
- 授权范围：【自有测试应用】
- ADB MCP：【已启用】
- Frida MCP：【已启用】
- 取证纪律：【先 adb devices 确认设备】
- 验收标准：【结论有证据路径】''');

    expect(card, isNotNull);
    expect(card!.device, isNull);
    expect(card.deviceSerial, 'emulator-5554');
    expect(card.deviceDisplay, 'emulator-5554');
  });

  test('ignores unrelated reverse-looking prompts', () {
    expect(AiWebReverseRequestCard.fromPrompt('逆向目标：【只是普通描述】'), isNull);
    expect(
      AiAndroidReverseRequestCard.fromPrompt('设备序列号：【emulator-5554】'),
      isNull,
    );
  });
}

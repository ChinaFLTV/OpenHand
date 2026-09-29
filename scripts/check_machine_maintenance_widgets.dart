import 'dart:io';

import 'support/flutter_widget_check.dart';

Future<void> main() async {
  final root = File.fromUri(Platform.script).parent.parent;
  final panel = await File(
    '${root.path}/lib/features/home/widgets/_home_machine_terminal_panel.dart',
  ).readAsString();
  final source = await File(
    '${root.path}/lib/features/home/widgets/_home_machine_maintenance.dart',
  ).readAsString();
  final header = panel.substring(
    panel.indexOf('class _MachineTerminalDialogHeader'),
    panel.indexOf(
      'class _MachineTerminalHistoryMetric',
      panel.indexOf('class _MachineTerminalDialogHeader'),
    ),
  );
  final button = panel.substring(
    panel.indexOf('class _MachineTerminalIconButton'),
    panel.indexOf('TerminalTheme _machineTerminalTheme'),
  );
  await runFlutterWidgetCheck(
    root: root,
    name: 'machine_maintenance',
    source:
        '''
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:openhand/features/machine_terminal/index.dart';
import 'package:openhand/features/machine_terminal/machine_maintenance.dart';
import 'package:openhand/shared/ui/animated_dialog.dart';
import 'package:openhand/shared/ui/animated_menu.dart';
import 'package:openhand/shared/util/timer_safety.dart';
import 'package:openhand/shared/ui/motion_preference.dart';
import 'package:openhand/shared/ui/motion_durations.dart';
import 'package:openhand/shared/ui/openhand_spacing.dart';
import 'package:openhand/shared/util/localized_text.dart';
import 'package:openhand/shared/util/byte_size_format.dart';
${source.replaceFirst("part of '../openhand_home_page.dart';", '')}
$header
$button
$_checks
''',
  );
}

const _checks =
    '''
class _MaintenanceFixture extends Fake with ChangeNotifier implements MachineTerminalFileService {
  int calls = 0;
  String platform = 'Linux';
  bool powershell = false;
  bool fail = false;
  Completer<String>? pending;
  @override
  Future<String> runMaintenanceCommand({required String sessionId, required String terminalId, required String command, bool windowsScript = false, MachineTerminalCommandShell commandShell = MachineTerminalCommandShell.posix, MachineTerminalUploadCancelCheck? isCancelled}) async {
    if (commandShell == MachineTerminalCommandShell.probe) return platform == 'Windows' ? (powershell ? 'OH_PS_Windows_NT' : 'OH_CMD_Windows_NT') : platform;
    expect(windowsScript, platform == 'Windows');
    calls++;
    if (Platform.environment['MAINTENANCE_REAL_DATA'] != null) {
      final samples = jsonDecode(File(Platform.environment['MAINTENANCE_REAL_DATA']!).readAsStringSync()) as Map;
      final key = command.contains('section processes') ? 'processes' : command.contains('section manager') ? 'services' : command.contains('section sockets') ? 'diagnostics' : calls == 1 ? 'overview' : 'overviewNext';
      return samples[key] as String;
    }
    if (fail) throw StateError('模拟连接中断');
    if (pending != null) return pending!.future;
    return '''
    "r'''"
    '''
__OH_OPS_platform__
Linux
__OH_OPS_host__
测试服务器
__OH_OPS_boot__
启动标识
__OH_OPS_system__
PRETTY_NAME="测试 Linux"
__OH_OPS_processor__
8 核处理器 · 测试数据
__OH_OPS_core_count__
8
__OH_OPS_filesystems__
Filesystem 1K-blocks Used Available Use% Mounted
/dev/sda1 524288000 235929600 288358400 45% /
/dev/sdb1 1048576000 387973120 660602880 37% /data
__OH_OPS_disks__
sda 100 0 2048 30 80 0 4096 40 0 70 80
__OH_OPS_network__
eth0: 1048576 100 0 0 0 0 0 0 524288 80 0 0 0 0 0 0
__OH_OPS_uptime__
1000 0
__OH_OPS_load__
0.21 0.45 0.32 1/100 2000
__OH_OPS_cpu__
cpu 30 0 10 960 0 0 0 0 0 0
cpu0 30 0 10 960 0 0 0 0 0 0
__OH_OPS_memory__
MemTotal: 8388608 kB
MemAvailable: 4194304 kB
SwapTotal: 2097152 kB
SwapFree: 1048576 kB
__OH_OPS_processes__
42	1	S	0	2	100	4096	20	300	测试进程
__COUNT__	1
__OH_OPS_page_size__
4096
__OH_OPS_manager__
systemd
__OH_OPS_services__
nginx.service loaded active running 测试服务
__OH_OPS_startup__
nginx.service enabled
__OH_OPS_sockets__
监听端口示例
__OH_OPS_status__
进程详情示例
__OH_OPS_end__
'''
    "'''"
    '''.replaceFirst('Linux', platform)
      .replaceFirst('systemd', platform == 'Darwin' ? 'launchd' : platform == 'Windows' ? 'Windows SCM' : 'systemd')
      .replaceFirst('测试进程\\n', '测试进程\\t启动标识\\n');
  }
}

void main() {
  if (Platform.environment['MAINTENANCE_REAL_DATA'] != null) {
    testWidgets('真实 macOS 数据四分区视觉检查', (tester) async {
      final service = _MaintenanceFixture()..platform = 'Darwin';
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      await tester.runAsync(() async {
        for (final entry in {'运维预览字体': Platform.environment['MAINTENANCE_FONT'], 'MaterialIcons': Platform.environment['MAINTENANCE_ICONS']}.entries) {
          if (entry.value != null) await (FontLoader(entry.key)..addFont(File(entry.value!).readAsBytes().then((bytes) => ByteData.sublistView(bytes)))).load();
        }
      });
      for (final brightness in [Brightness.light, Brightness.dark]) {
        await tester.pumpWidget(ChangeNotifierProvider<MachineTerminalFileService>.value(value: service,
          child: MaterialApp(theme: ThemeData(fontFamily: '运维预览字体', colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff526914), brightness: brightness)),
            home: const MediaQuery(data: MediaQueryData(size: Size(1440, 1000)), child: Scaffold(body: RepaintBoundary(key: ValueKey('实机预览'), child: _MachineMaintenanceDialog(sessionId: '会话', terminalId: '本机终端')))))));
        await tester.pumpAndSettle();
        for (var index = 0; index < _maintenanceTabs.length; index++) {
          await tester.tap(find.text(_maintenanceTabs[index]));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('实机预览')));
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
            await File('/tmp/maintenance-real-\$index-\${brightness.name}.png').writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox());
      }
      await tester.binding.setSurfaceSize(null);
    });
    return;
  }
  test('系统摘要与跨平台连接解析保留时间和 IPv6 地址', () {
    final mac = MachineMaintenanceSnapshot({'platform': 'Darwin', 'system': 'ProductVersion: 27.0.1\\nDarwin host 27.0.0 Darwin Kernel Version 27.0.0: Tue 13:20:00', 'sockets': 'tcp46 0 0 *.80 *.* LISTEN\\nudp4 0 0 127.0.0.1.53 *.* 0', 'host': 'host'});
    expect(_maintenanceFacts(mac)['系统版本'], '27.0.1');
    expect(_maintenanceFacts(mac)['内核版本'], '27.0.0');
    expect(_maintenanceConnections(mac).first, ['TCP46', '*.80', '*.*', 'LISTEN']);
    final linux = MachineMaintenanceSnapshot({'platform': 'Linux', 'sockets': 'tcp LISTEN 0 128 [::]:22 [::]:*'});
    expect(_maintenanceConnections(linux).single, ['TCP', '[::]:22', '[::]:*', 'LISTEN']);
    final windows = MachineMaintenanceSnapshot({'platform': 'Windows', 'sockets': 'TCP [::1]:80 [::]:0 LISTENING 20'});
    expect(_maintenanceConnections(windows).single, ['TCP', '[::1]:80', '[::]:0', 'LISTENING']);
  });

  testWidgets('运维分区适配浅深主题、大字体与窄窗口', (tester) async {
    final service = _MaintenanceFixture();
    final font = Platform.environment['MAINTENANCE_FONT'];
    if (font != null) {
      await tester.runAsync(() async {
        final loader = FontLoader('运维预览字体')..addFont(File(font).readAsBytes().then((bytes) => ByteData.sublistView(bytes)));
        await loader.load();
        final icons = Platform.environment['MAINTENANCE_ICONS'];
        if (icons != null) {
          final loader = FontLoader('MaterialIcons')..addFont(File(icons).readAsBytes().then((bytes) => ByteData.sublistView(bytes)));
          await loader.load();
        }
      });
    }
    for (final width in [580.0, 1280.0]) {
      for (final brightness in [Brightness.light, Brightness.dark]) {
        await tester.binding.setSurfaceSize(Size(width, 900));
        await tester.pumpWidget(ChangeNotifierProvider<MachineTerminalFileService>.value(value: service,
          child: MaterialApp(theme: ThemeData(fontFamily: font == null ? null : '运维预览字体', colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal, brightness: brightness)),
            home: MediaQuery(data: MediaQueryData(size: Size(width, 900), textScaler: TextScaler.linear(width == 580 ? 1.5 : 1)),
              child: const Scaffold(body: RepaintBoundary(key: ValueKey('运维预览'), child: _MachineMaintenanceDialog(sessionId: '会话', terminalId: '终端')))))));
        await tester.pumpAndSettle();
        for (final label in ['进程管理', '系统服务', '网络与诊断', '运行总览']) {
          await tester.ensureVisible(find.text(label));
          await tester.tap(find.text(label));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          if (label == '进程管理') {
            expect(find.text('测试进程'), findsOneWidget);
            await tester.ensureVisible(find.text('测试进程'));
      await tester.tap(find.text('测试进程'));
            await tester.pumpAndSettle();
            expect(find.text('进程 42 · 测试进程'), findsOneWidget);
            expect(find.text('终止进程'), findsOneWidget);
            await tester.tap(find.byTooltip('Close').last);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          }
        }
        if (width == 1280 && brightness == Brightness.light && Platform.environment['MAINTENANCE_PREVIEW'] != null) {
          final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('运维预览')));
          await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(Platform.environment['MAINTENANCE_PREVIEW']!).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox());
      }
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 与 Windows Shell 策略显示对应动作', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    for (final target in [('Darwin', false), ('Windows', false), ('Windows', true)]) {
      final service = _MaintenanceFixture()..platform = target.\$1..powershell = target.\$2;
      await tester.pumpWidget(ChangeNotifierProvider<MachineTerminalFileService>.value(value: service,
        child: const MaterialApp(home: Scaffold(body: _MachineMaintenanceDialog(sessionId: '会话', terminalId: '终端')))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('进程管理'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('测试进程'));
      await tester.tap(find.text('测试进程'));
      await tester.pumpAndSettle();
      expect(find.text('终止进程'), findsOneWidget);
      expect(find.text('暂停进程'), target.\$1 == 'Darwin' ? findsOneWidget : findsNothing);
      await tester.tap(find.byTooltip('Close').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('系统服务'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('nginx.service').first);
      await tester.pumpAndSettle();
      expect(find.text('启动服务'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('首次失败保留摘要结构并支持重新采集', (tester) async {
    final service = _MaintenanceFixture()..fail = true;
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    await tester.pumpWidget(ChangeNotifierProvider<MachineTerminalFileService>.value(value: service,
      child: const MaterialApp(home: Scaffold(body: _MachineMaintenanceDialog(sessionId: '会话', terminalId: '终端')))));
    await tester.pumpAndSettle();
    expect(find.text('机器状态暂不可用'), findsOneWidget);
    expect(find.text('重新采集'), findsOneWidget);

    expect(tester.takeException(), isNull);
    service.fail = false;
    await tester.ensureVisible(find.text('重新采集'));
    await tester.tap(find.text('重新采集'));
    await tester.pumpAndSettle();
    expect(service.calls, 2);
    expect(find.text('CPU 使用率'), findsOneWidget);
    expect(find.text('重新采集'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('长列表卡片高度有界且可滚动到底部', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 900));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: SizedBox(width: 600,
      child: _MaintenanceCard(title: '长列表', child: Column(children: List.generate(200, (index) => Text('列表条目 \$index')))),
    )))));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(_MaintenanceCard)).height, lessThan(400));
    await tester.ensureVisible(find.text('列表条目 199'));
    await tester.pumpAndSettle();
    expect(find.text('列表条目 199').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('刷新间隔、串行采集、失败暂停与关闭清理', (tester) async {
    final service = _MaintenanceFixture();
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    await tester.pumpWidget(ChangeNotifierProvider<MachineTerminalFileService>.value(value: service,
      child: const MaterialApp(home: Scaffold(body: _MachineMaintenanceDialog(sessionId: '会话', terminalId: '终端')))));
    await tester.pumpAndSettle();
    expect(service.calls, 1);
    await tester.tap(find.byTooltip('开启自动刷新（当前分区）'));
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(service.calls, 2);
    await tester.tap(find.text('10 秒'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('5 秒').last);
    await tester.pumpAndSettle();
    service.pending = Completer<String>();
    await tester.pump(const Duration(seconds: 5));
    final count = service.calls;
    await tester.pump(const Duration(seconds: 30));
    expect(service.calls, count);
    service.pending!.completeError(StateError('模拟采集失败'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 30));
    expect(service.calls, count);
    expect(find.textContaining('已暂停自动重试'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 60));
    expect(service.calls, count);
    expect(tester.takeException(), isNull);
    await tester.binding.setSurfaceSize(null);
  });
}
''';

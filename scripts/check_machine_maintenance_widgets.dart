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
import 'package:openhand/app/support/silent_log.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:openhand/app/model/app_settings_snapshot.dart';
import 'package:openhand/app/state/settings_controller.dart';
import 'package:openhand/app/state/settings_store.dart';
import 'package:openhand/features/machine_terminal/index.dart';
import 'package:openhand/l10n/app_localizations.dart';
import 'package:openhand/app/theme/openhand_theme.dart';
import 'package:openhand/app/theme/openhand_theme_preset.dart';
import 'package:openhand/app/theme/openhand_status_colors.dart';
import 'package:openhand/features/machine_terminal/machine_maintenance.dart';
import 'package:openhand/shared/ui/animated_dialog.dart';
import 'package:openhand/shared/ui/animated_menu.dart';
import 'package:openhand/shared/util/timer_safety.dart';
import 'package:openhand/shared/ui/motion_preference.dart';
import 'package:openhand/shared/ui/motion_durations.dart';
import 'package:openhand/shared/ui/openhand_spacing.dart';
import 'package:openhand/shared/ui/openhand_ops_charts.dart';
import 'package:openhand/shared/ui/openhand_ops_press_scale.dart';
import 'package:openhand/shared/ui/openhand_console_log_panel.dart';
import 'package:openhand/shared/ui/openhand_table_pagination.dart';
import 'package:openhand/shared/util/localized_text.dart';
import 'package:openhand/shared/util/byte_size_format.dart';
${source.replaceFirst("part of '../openhand_home_page.dart';", '')}
$header
$button
${_checks.replaceAll('MaterialApp(', '_SettingsApp(')}
$_settingsHarness
''',
  );
}

const _checks =
    '''
class _MaintenanceFixture extends Fake with ChangeNotifier implements MachineTerminalFileService {
  int calls = 0;
  int probes = 0;
  String lastCommand = "";
  String platform = 'Linux';
  bool powershell = false;
  bool fail = false;
  String? gpuOutput;
  Object? failure;
  Completer<String>? pending;
  MachineTerminalUploadCancelCheck? cancelled;
  @override
  Future<String> runMaintenanceCommand({required String sessionId, required String terminalId, required String command, bool windowsScript = false, MachineTerminalCommandShell commandShell = MachineTerminalCommandShell.posix, MachineTerminalUploadCancelCheck? isCancelled}) async {
    if (command.contains('OH_SHELL_') || command == 'ver') return 'OH_SHELL_bash 5.2';
    if (command == machineTerminalShellProbe) probes++;
    if (commandShell == MachineTerminalCommandShell.probe) return platform == 'Windows' ? (powershell ? 'OH_PS_Windows_NT' : 'OH_CMD_Windows_NT') : platform;
    expectSync(windowsScript, platform == 'Windows');
    cancelled = isCancelled;
    calls++;
    lastCommand = command;
    if (Platform.environment['MAINTENANCE_REAL_DATA'] != null) {
      final samples = jsonDecode(File(Platform.environment['MAINTENANCE_REAL_DATA']!).readAsStringSync()) as Map;
      final key = command.contains('section processes') ? 'processes' : command.contains('section manager') ? 'services' : command.contains('section sockets') ? 'diagnostics' : calls == 1 ? 'overview' : 'overviewNext';
      return samples[key] as String;
    }
    if (failure != null) throw failure!;
    if (fail) throw StateError('模拟连接中断');
    if (pending != null) return pending!.future;
    if (gpuOutput != null && command.contains('section gpu_')) return gpuOutput!;
    if (command.contains('section gpu_nvidia')) return '__OH_OPS_platform__\\nLinux\\n__OH_OPS_host__\\nGPU主机\\n__OH_OPS_gpu_nvidia__\\nGPU-1,NVIDIA Test,550.1,00000000:01:00.0,45,1024,8192,60,80.5,150,1800,7000,0,P2\\n__OH_OPS_gpu_processes__\\nGPU-1,42,compute,128\\n__OH_OPS_end__\\n';
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
__OH_OPS_service_metrics__
MainPID=42
MemoryCurrent=1048576
CPUUsageNSec=2000000000
TasksCurrent=3
NRestarts=0
ExecMainStatus=0
Id=nginx.service

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
  setUp(() async { _testSettings = await SettingsController.create(store: _MemorySettingsStore()); });
  tearDown(() { _testSettings.dispose(); });
  test('采集并发数持久化、校验及保存失败回滚', () async {
    final store = _MemorySettingsStore();
    final settings = await SettingsController.create(store: store);
    expect(await settings.updateMaintenanceWorkers(8), isTrue);
    final reopened = await SettingsController.create(store: store);
    expect(reopened.maintenanceWorkers, 8);
    expect(await settings.updateMaintenanceWorkers(3), isFalse);
    store.fail = true;
    expect(await settings.updateMaintenanceWorkers(2), isFalse);
    expect(settings.maintenanceWorkers, 8);
    expect(AppSettingsSnapshot.normalizeMaintenanceWorkers(3), 4);
    expect(AppSettingsSnapshot.normalizeMaintenanceWorkers(null), 4);
    settings.dispose();
    reopened.dispose();
  });
  testWidgets('重新打开弹窗沿用已保存的采集并发数', (tester) async {
    await tester.runAsync(() => _testSettings.updateMaintenanceWorkers(8));
    final service = _MaintenanceFixture();
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    for (var i = 0; i < 2; i++) {
      await tester.pumpWidget(ChangeNotifierProvider<MachineTerminalFileService>.value(value: service,
        child: const MaterialApp(locale: Locale('zh'), localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales, home: Scaffold(body: _MachineMaintenanceDialog(sessionId: '会话', terminalId: '终端')))));
      await tester.pumpAndSettle();
      expect(find.text('最多 8 个采集进程'), findsOneWidget);
      expect(service.lastCommand, contains('oh_workers=8'));
      await tester.pumpWidget(const SizedBox());
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('长错误信息有可见滚动入口，更新为短信息后恢复完整显示', (tester) async {
    Widget host(String message) => MaterialApp(home: Scaffold(body: Align(alignment: Alignment.topCenter,
      child: SizedBox(width: 360, child: _MaintenanceNotice(message: message, error: true)))));
    await tester.pumpWidget(host(List.filled(60, '错误详情').join('\\n')));
    await tester.pumpAndSettle();
    final state = tester.state<_MaintenanceNoticeState>(find.byType(_MaintenanceNotice));
    expect(state._scrollController.position.maxScrollExtent, greaterThan(0));
    expect(tester.widget<Scrollbar>(find.byType(Scrollbar)).thumbVisibility, isTrue);
    state._scrollController.jumpTo(state._scrollController.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(state._scrollController.position.extentAfter, 0);
    await tester.pumpWidget(host('连接已恢复')); await tester.pumpAndSettle();
    expect(state._scrollController.offset, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('错误页在大字号和窄屏下完整展示重试按钮及本地化超时信息', (tester) async {
    for (final locale in [const Locale('zh'), const Locale('en'), const Locale('de'), const Locale('fr'), const Locale('ja'), const Locale('zh', 'Hant')]) {
      for (final size in [const Size(430, 560), const Size(1280, 800)]) {
        await tester.binding.setSurfaceSize(size);
        final service = _MaintenanceFixture()..failure = TimeoutException('模拟命令超时');
        await tester.pumpWidget(ChangeNotifierProvider<MachineTerminalFileService>.value(
          value: service, child: MaterialApp(locale: locale,
          theme: ThemeData(filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18)))),
          localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.5)), child: child!),
          home: const Scaffold(body: _MachineMaintenanceDialog(sessionId: '会话', terminalId: '终端')))));
        await tester.pumpAndSettle();
        final l = AppLocalizations.of(tester.element(find.byType(_MachineMaintenanceDialog)))!;
        expect(find.text(l.maintenanceCommandTimedOut), findsOneWidget);
        final label = find.text(l.maintenanceRetry);
        await tester.ensureVisible(label); await tester.pumpAndSettle();
        final button = find.ancestor(of: label, matching: find.byType(FilledButton));
        expect(tester.getRect(button).contains(tester.getRect(label).topLeft), isTrue);
        expect(tester.getRect(button).contains(tester.getRect(label).bottomRight), isTrue);
        expect(find.textContaining('__OPENHAND_'), findsNothing);
        expect(tester.takeException(), isNull);
        service.failure = null;
        await tester.tap(label); await tester.pumpAndSettle();
        expect(find.text(l.maintenanceCommandTimedOut), findsNothing);
        await tester.pumpWidget(const SizedBox());
      }
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('账户健康板块显示结构化账户、时区与不可用状态', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    final service = _MaintenanceFixture();
    await tester.pumpWidget(ChangeNotifierProvider<MachineTerminalFileService>.value(
      value: service, child: const MaterialApp(locale: Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: _MachineMaintenanceDialog(sessionId: '会话', terminalId: '终端')))));
    await tester.pumpAndSettle();
    final state = tester.state<_MachineMaintenanceDialogState>(find.byType(_MachineMaintenanceDialog));
    state.setState(() {
      state._tab = 6;
      state._snapshots[6] = MachineMaintenanceSnapshot({
        'platform': 'Linux', 'health_accounts': '@user\\tuid\\thome\\tshell\\nreader\\t1000\\t/home/reader\\t/bin/bash',
        'health_accounts_status': '0', 'health_temperature_status': '125',
        'health_clock': '2026-09-29 22:00:00 CST +0800', 'health_clock_status': '0',
      });
    });
    await tester.pumpAndSettle();
    expect(find.text('账户与健康'), findsOneWidget);
    expect(find.text('reader'), findsOneWidget);
    expect(find.text('平台未提供此数据'), findsOneWidget);
    expect(find.textContaining('+0800'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox()); await tester.binding.setSurfaceSize(null);
  });

  testWidgets('健康字段结构化展示，错误原文默认折叠且宽窄屏无溢出', (tester) async {
    await tester.runAsync(() async {
      for (final entry in {'运维预览字体': Platform.environment['MAINTENANCE_FONT'], 'MaterialIcons': Platform.environment['MAINTENANCE_ICONS']}.entries) {
        if (entry.value != null) await (FontLoader(entry.key)..addFont(File(entry.value!).readAsBytes().then((bytes) => ByteData.sublistView(bytes)))).load();
      }
    });
    final service = _MaintenanceFixture();
    await tester.binding.setSurfaceSize(const Size(1440, 1100));
    await tester.pumpWidget(ChangeNotifierProvider<MachineTerminalFileService>.value(value: service,
      child: MaterialApp(builder: (context, child) => LayoutBuilder(builder: (context, constraints) => MediaQuery(data: MediaQuery.of(context).copyWith(size: constraints.biggest), child: child!)),
        theme: ThemeData(fontFamily: Platform.environment['MAINTENANCE_FONT'] == null ? null : '运维预览字体'),
        locale: const Locale('zh'), localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: RepaintBoundary(key: ValueKey('健康预览'), child: _MachineMaintenanceDialog(sessionId: '会话', terminalId: '终端'))))));
    await tester.pumpAndSettle();
    final state = tester.state<_MachineMaintenanceDialogState>(find.byType(_MachineMaintenanceDialog));
    state.setState(() {
      state._tab = 6;
      state._snapshots[6] = MachineMaintenanceSnapshot({
        'platform': 'Darwin',
        for (final key in machineHealthSections) 'health_\${key}_status': '0',
        'health_system': 'Kernel: Darwin\\nHostname: example\\nKernelRelease: 27.0.0\\nArchitecture: arm64\\nProductName: macOS\\nProductVersion: 27.0.1',
        'health_sessions': 'reader console Sep 29 09:41 08:30 608',
        'health_logins': 'reader ttys000 Tue Sep 29 19:22 still logged in',
        'health_accounts': '@user\\tuid\\thome\\tshell\\nreader\\t501\\t/Users/reader\\t/bin/zsh',
        'health_password': '<plist><dict><key>policyContent</key><string>policyAttributePassword matches .{4,}+</string><key>policyIdentifier</key><string>minimumLength</string></dict></plist>',
        'health_ssh': 'sshd: no hostkeys available -- exiting.',
        'health_temperature': 'Note: No thermal warning level has been recorded\\nNote: No performance warning level has been recorded\\nNote: No CPU power status has been recorded',
        'health_power': "Now drawing from 'AC Power'\\n-InternalBattery-0 (id=123) 80%; AC attached; not charging present: true\\nCycleCount: 42",
        'health_clock': '2026-09-29 20:00:00 CST +0800\\n2026-09-29 12:00:00 UTC',
        'health_sync': 'You need administrator access to run this tool... exiting!',
        'health_ntp': 'configured: /etc/ntp.conf\\nNetwork Time Server: time.apple.com',
      });
    });
    await tester.pumpAndSettle();
    expect(find.text('系统名称'), findsOneWidget);
    expect(find.textContaining('<plist>'), findsNothing);
    expect(find.text('You need administrator access to run this tool... exiting!'), findsNothing);
    expect(tester.takeException(), isNull);
    if (Platform.environment['MAINTENANCE_FONT'] != null) {
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('健康预览')));
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('/tmp/maintenance-health-preview.png').writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.binding.setSurfaceSize(const Size(420, 900));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('控制台日志暗色正文、全文详情与窄屏折叠滚动稳定', (tester) async {
    await tester.binding.setSurfaceSize(const Size(760, 700));
    await tester.runAsync(() async {
      if (Platform.environment['MAINTENANCE_FONT'] != null) await (FontLoader('monospace')..addFont(File(Platform.environment['MAINTENANCE_FONT']!).readAsBytes().then((bytes) => ByteData.sublistView(bytes)))).load();
    });
    final buffer = MachineLogBuffer()..append('[info] 服务已启动\\n[warning] 连接重试\\n[error] 请求超时');
    await tester.pumpWidget(MaterialApp(theme: ThemeData(fontFamily: Platform.environment['MAINTENANCE_FONT'] == null ? null : '运维预览字体'), locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => LayoutBuilder(builder: (context, box) => MediaQuery(data: MediaQuery.of(context).copyWith(size: box.biggest), child: child!)),
      home: Scaffold(body: RepaintBoundary(key: const ValueKey('日志预览'),
        child: Material(child: _MaintenanceLogBrowser(buffers: {'system': buffer}, data: MachineMaintenanceSnapshot({'platform': 'Linux'})))))));
    await tester.pumpAndSettle();
    expect(find.byType(OpenHandConsoleFrame), findsOneWidget);
    expect(tester.widget<Text>(find.text('[error] 请求超时')).style!.color, OpenHandConsolePalette.text);
    if (Platform.environment['MAINTENANCE_FONT'] != null) {
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('日志预览')));
      await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1.5);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('/tmp/maintenance-log-console-preview.png').writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
      });
    }
    await tester.tap(find.text('[error] 请求超时')); await tester.pumpAndSettle();
    expect(find.byType(OpenHandConsoleText), findsOneWidget);
    expect(tester.widget<SelectableText>(find.byType(SelectableText)).textSpan!.toPlainText(), '[error] 请求超时');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(width: 300, child: ExpansionTile(
      key: const PageStorageKey('详情展开'), title: const Text('详情'), children: [
        OpenHandConsoleText(title: '日志', text: List.filled(100, '完整日志').join('\\n')),
      ])))));
    await tester.tap(find.text('详情')); await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox()); await tester.binding.setSurfaceSize(null);
  });

  testWidgets('日志轮转卡片合并归档字段并按类别切换，窄屏展开保留日志区域', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 620));
    await tester.pumpWidget(MaterialApp(theme: ThemeData(fontFamily: Platform.environment['MAINTENANCE_FONT'] == null ? null : '运维预览字体'), locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales,
      home: RepaintBoundary(key: const ValueKey('轮转预览'), child: Scaffold(body: _MaintenanceLogBrowser(buffers: {}, data: MachineMaintenanceSnapshot({
        'platform': 'Darwin',
        'log_rotation': '-rw-r--r-- 1 root wheel 384599 Sep 29 18:41:39 2026 /var/log/system.log.0',
        'log_config': '/etc/logrotate.conf\\nweekly\\nrotate 7',
        'log_storage': '4096 /var/log',
      }))))));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ExpansionTile)); await tester.pumpAndSettle();
    expect(find.text('/var/log/system.log.0'), findsOneWidget);
    expect(find.text(formatByteSize(384599)), findsOneWidget);
    expect(tester.getSize(find.byType(OpenHandConsoleFrame)).height, greaterThan(80));
    if (Platform.environment['MAINTENANCE_FONT'] != null) {
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('轮转预览')));
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1.5);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('/tmp/maintenance-log-rotation-preview.png').writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.tap(find.text('轮转策略 · 2')); await tester.pumpAndSettle();
    expect(find.text('/etc/logrotate.conf'), findsWidgets);
    await tester.tap(find.text('日志目录大小 · 1')); await tester.pumpAndSettle();
    expect(find.text(formatByteSize(4096 * 1024)), findsOneWidget);
    expect(find.text('/var/log'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox()); await tester.binding.setSurfaceSize(null);
  });

  testWidgets('日志追加保留阅读锚点并适配窄屏，损坏数据不清空记录', (tester) async {
    final buffer = MachineLogBuffer()..append(List.generate(120, (i) => '记录 \$i').join('\\n'));
    var revision = 0;
    Widget host() => MaterialApp(locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: _MaintenanceLogBrowser(buffers: {'system': buffer},
        data: MachineMaintenanceSnapshot.parse('__OH_OPS_platform__\\nLinux\\n__OH_OPS_host__\\n主机\$revision\\n__OH_OPS_log_rotation__\\n"/var/log/app.log" 2026-9-29-0:0:0\\n__OH_OPS_log_config__\\n/etc/logrotate.conf\\nweekly\\nrotate 7\\n__OH_OPS_end__\\n'))));
    await tester.binding.setSurfaceSize(const Size(760, 700));
    await tester.pumpWidget(host()); await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final state = tester.state<_MaintenanceLogBrowserState>(find.byType(_MaintenanceLogBrowser));
    state.setState(() => state._follow = false);
    state._scroll.jumpTo(640); await tester.pumpAndSettle();
    buffer.append('记录 119\\n新日志'); revision++;
    await tester.pumpWidget(host()); await tester.pumpAndSettle();
    expect(state._scroll.offset, 640);
    expect(buffer.entries.last.message, '新日志');
    buffer.append('dmesg: Operation not permitted'); revision++;
    await tester.pumpWidget(host()); await tester.pumpAndSettle();
    expect(find.text('日志源暂不可用'), findsOneWidget);
    expect(buffer.entries.length, 121);
    await tester.enterText(find.byType(TextField), '新日志'); await tester.pumpAndSettle();
    expect(state._visible.length, 1);
    expect(tester.takeException(), isNull);
    await tester.binding.setSurfaceSize(const Size(420, 900));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ExpansionTile)); await tester.pumpAndSettle();
    expect(find.text('/var/log/app.log'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox()); await tester.binding.setSurfaceSize(null);
  });

  testWidgets('分页跳页数字在主题约束、字号和焦点变化下保持居中', (tester) async {
    for (final height in [32.0, 34.0]) {
      for (final scale in [1.0, 1.5]) {
        for (final enabled in [true, false]) {
          await tester.pumpWidget(MaterialApp(
            theme: ThemeData(inputDecorationTheme: InputDecorationTheme(
              constraints: BoxConstraints.tightFor(height: height == 34 ? 34 : 48),
              contentPadding: EdgeInsets.all(16),
            )),
            home: Scaffold(body: Center(child: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: OpenHandTablePagination(total: 4000, page: 125, pageSize: 20,
                controlHeight: height, enabled: enabled, onPageChanged: (_) {}),
            ))),
          ));
          await tester.pumpAndSettle();
          final field = find.byType(TextField);
          void checkCenter() {
            final editable = tester.state<EditableTextState>(find.byType(EditableText)).renderEditable;
            final box = editable.getBoxesForSelection(
              const TextSelection(baseOffset: 0, extentOffset: 3)).single;
            final textCenter = editable.localToGlobal(box.toRect().center);
            final frame = find.ancestor(of: field, matching: find.byType(AnimatedContainer)).first;
            expect(textCenter.dy, closeTo(tester.getCenter(frame).dy, 1.0));
            expect(tester.takeException(), isNull);
          }
          checkCenter();
          if (enabled) {
            await tester.tap(field);
            await tester.pumpAndSettle();
            checkCenter();
          }
          await tester.pumpWidget(const SizedBox());
        }
      }
    }
  });

  test('图表按指标标识插值，增删和重排不会串值', () {
    final tween = _MaintenanceSeriesTween(end: {'写入': 40, '接收': 10})
      ..begin = {'读取': 100, '写入': 20};
    expect(tween.lerp(.5), {'写入': 30.0, '接收': 5.0});
    expect(tween.lerp(1).keys, ['写入', '接收']);
  });

  testWidgets('占比和排行保留零值，未变数据复用动画目标，大字体不溢出', (tester) async {
    var count = 12;
    late StateSetter update;
    await tester.pumpWidget(MaterialApp(locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: StatefulBuilder(builder: (context, setState) {
        update = setState;
        return MediaQuery(data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: SizedBox(width: 260, child: _MaintenanceVisual(donut: true, segments: [
            OpenHandChartSegment(label: 'Running', value: count, color: Colors.teal),
            const OpenHandChartSegment(label: 'Stopped', value: 0, color: Colors.orange),
          ])));
      }))));
    await tester.pumpAndSettle();
    final state = tester.state<_MaintenanceVisualState>(find.byType(_MaintenanceVisual));
    final target = state._target;
    update(() {});
    await tester.pumpAndSettle();
    expect(identical(state._target, target), isTrue);
    expect(find.text('0'), findsOneWidget);
    update(() => count = 24);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(identical(state._target, target), isFalse);
    await tester.pumpAndSettle();
    expect(find.text('24'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('端点关系合并连接并排除监听占位地址，日志保留完整消息', (tester) async {
    await tester.pumpWidget(MaterialApp(locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SizedBox(width: 300, child: Column(children: [
        const _MaintenanceConnectionGraph(rows: [
          ['TCP', '127.0.0.1:20', '[::1]:30', 'ESTAB'],
          ['TCP', '127.0.0.1:20', '[::1]:30', 'ESTAB'],
          ['TCP', '*:80', '*:*', 'LISTEN'],
          ['UDP', '*:53', '*.*', 'UNCONN'],
        ]),
        _MaintenanceLogTimeline(rows: List.generate(30, (i) => ['12:00:00', '完整日志消息 \$i'])),
      ])))));
    await tester.pumpAndSettle();
    expect(find.text('[::1]:30'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('*:80'), findsNothing);
    expect(find.text('*:53'), findsNothing);
    final logText = tester.widget<SelectableText>(find.descendant(
      of: find.byType(_MaintenanceLogTimeline), matching: find.byType(SelectableText)));
    expect(logText.textSpan!.toPlainText(), contains('完整日志消息 29'));
    expect(logText.textSpan!.toPlainText(), contains('完整日志消息 0'));
    expect(logText.maxLines, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });


  testWidgets('运维可视化组合适配浅深主题并保留空值状态', (tester) async {
    await tester.binding.setSurfaceSize(const Size(960, 1000));
    if (Platform.environment['MAINTENANCE_FONT'] != null) {
      await tester.runAsync(() async {
        await (FontLoader('运维预览字体')..addFont(File(Platform.environment['MAINTENANCE_FONT']!).readAsBytes().then((bytes) => ByteData.sublistView(bytes)))).load();
      });
    }
    for (final brightness in [Brightness.light, Brightness.dark]) {
      await tester.pumpWidget(MaterialApp(locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(fontFamily: Platform.environment['MAINTENANCE_FONT'] != null ? '运维预览字体' : null,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal, brightness: brightness)),
        home: Builder(builder: (context) => Scaffold(body: RepaintBoundary(key: const ValueKey('可视化预览'),
          child: ColoredBox(color: Theme.of(context).colorScheme.surface,
            child: Padding(padding: const EdgeInsets.all(16), child: _MaintenanceGrid(minWidth: 380, children: [
              const _MaintenanceCard(title: 'Resource gauges', child: Wrap(spacing: 20, runSpacing: 12, children: [
                _MaintenanceGauge(label: 'CPU', value: .63, color: Colors.teal),
                _MaintenanceGauge(label: 'Memory', value: .42, color: Colors.indigo),
                _MaintenanceGauge(label: 'Swap', value: null, color: Colors.purple),
              ])),
              const _MaintenanceCard(title: 'Memory allocation', child: _MaintenanceVisual(donut: true, centerLabel: '32 GB', segments: [
                OpenHandChartSegment(label: 'Used', value: 42, valueLabel: '13.4 GB', color: Colors.teal),
                OpenHandChartSegment(label: 'Available', value: 58, valueLabel: '18.6 GB', color: Colors.indigo),
              ])),
              const _MaintenanceCard(title: 'Process resource ranking', child: _MaintenanceVisual(segments: [
                OpenHandChartSegment(label: '1042 · postgres', value: 74, valueLabel: '74%', color: Colors.teal),
                OpenHandChartSegment(label: '2501 · nginx', value: 32, valueLabel: '32%', color: Colors.indigo),
                OpenHandChartSegment(label: '3188 · worker', value: 18, valueLabel: '18%', color: Colors.purple),
              ])),
              const _MaintenanceCard(title: 'Endpoint connections', child: _MaintenanceConnectionGraph(rows: [
                ['TCP', '10.0.0.1:44001', '10.0.0.2:5432', 'ESTAB'],
                ['TCP', '10.0.0.1:44001', '10.0.0.2:5432', 'ESTAB'],
                ['TCP', '10.0.0.1:44123', '10.0.0.3:6379', 'ESTAB'],
              ])),
              const _MaintenanceCard(title: 'Recent logs', child: _MaintenanceLogTimeline(rows: [
                ['2026-09-29 17:30:01', 'worker[3188]: Batch completed: 128 records'],
                ['2026-09-29 17:30:03', 'nginx[2501]: Upstream connection established'],
              ])),
            ]))))))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('—'), findsOneWidget);
      if (Platform.environment['MAINTENANCE_VISUAL_PREVIEW'] != null) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('可视化预览')));
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('/tmp/maintenance-visual-\${brightness.name}.png').writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    }
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('趋势按实际时间插值且刷新平滑过渡，减少动画直接完成', (tester) async {
    var reduced = false;
    var points = [(time: 0.0, value: .1), (time: 1000.0, value: .8), (time: 10000.0, value: .2)];
    late StateSetter update;
    await tester.pumpWidget(MaterialApp(locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: StatefulBuilder(builder: (context, setState) {
        update = setState;
        return MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
          child: SizedBox(width: 360, height: 190, child: _MaintenanceTrend(points: points)));
      }))));
    await tester.pumpAndSettle();
    final state = tester.state<_MaintenanceTrendState>(find.byType(_MaintenanceTrend));
    expect(state._to[12], closeTo(.8, .001));
    update(() => points = [...points, (time: 13000.0, value: .9)]);
    await tester.pump();
    expect(state._animation.isAnimating, isTrue);
    await tester.pump(const Duration(milliseconds: 60));
    expect(state._animation.value, greaterThan(0));
    expect(state._animation.value, lessThan(1));
    await tester.pumpAndSettle();
    expect(state._to.last, closeTo(.9, .001));
    update(() { reduced = true; points = [...points, (time: 17000.0, value: .3)]; });
    await tester.pump();
    expect(state._animation.value, 1);
    expect(state._to.last, closeTo(.3, .001));
    state.setState(() { state._window = 5000; state._anchorEnd = 11000; state._update(animate: false); });
    await tester.pump();
    update(() => points = [...points, (time: 21000.0, value: .6)]);
    await tester.pumpAndSettle();
    expect(state._start, 6000);
    expect(state._end, 11000);
    update(() => points = [(time: 15000.0, value: .2), (time: 21000.0, value: .6)]);
    await tester.pumpAndSettle();
    expect(state._start, 15000);
    expect(state._end, 20000);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('趋势双指缩放保持时间锚点，平移有界且双击恢复全范围', (tester) async {
    await tester.pumpWidget(MaterialApp(locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SizedBox(width: 360, height: 190,
        child: _MaintenanceTrend(points: List.generate(60,
          (i) => (time: i * 1000.0, value: i / 60)))))));
    await tester.pumpAndSettle();
    final state = tester.state<_MaintenanceTrendState>(find.byType(_MaintenanceTrend));
    final center = tester.getCenter(find.byType(_MaintenanceTrend));
    final left = await tester.startGesture(center - const Offset(35, 0), pointer: 1);
    final right = await tester.startGesture(center + const Offset(35, 0), pointer: 2);
    await tester.pump();
    await left.moveTo(center - const Offset(45, 0));
    await right.moveTo(center + const Offset(45, 0));
    await tester.pump();
    await left.moveTo(center - const Offset(100, 0));
    await right.moveTo(center + const Offset(100, 0));
    await tester.pump();
    expect(state._end - state._start, lessThan(59000));
    expect(state._end - state._start, greaterThanOrEqualTo(1000));
    await left.up(); await right.up();
    await tester.drag(find.byType(_MaintenanceTrend), const Offset(500, 0));
    await tester.pumpAndSettle();
    expect(state._start, greaterThanOrEqualTo(0));
    expect(state._end, lessThanOrEqualTo(59000));
    await tester.tapAt(center); await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(center); await tester.pumpAndSettle();
    expect(state._window, isNull);
    expect(state._start, 0);
    expect(state._end, 59000);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

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
          child: MaterialApp(locale: const Locale('zh'), localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, theme: ThemeData(fontFamily: '运维预览字体', colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff526914), brightness: brightness)),
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
        final sample = jsonDecode(File(Platform.environment['MAINTENANCE_REAL_DATA']!).readAsStringSync()) as Map;
        final data = MachineMaintenanceSnapshot.parse(sample['overview'] as String);
        await tester.pumpWidget(MaterialApp(locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(fontFamily: '运维预览字体', colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff526914), brightness: brightness)),
          home: Scaffold(body: RepaintBoundary(key: const ValueKey('指标预览'), child: Padding(
            padding: const EdgeInsets.all(24), child: ListView(children: [
              for (final key in ['blocks', 'disks']) Padding(padding: const EdgeInsets.only(bottom: 12),
                child: _MaintenanceCard(title: key == 'blocks' ? '块设备与 RAID' : '磁盘累计计数', scrollBody: false,
                  child: _MaintenanceMetricContent(data: data, section: key))),
            ]))))));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final metricsBoundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('指标预览')));
        await tester.runAsync(() async {
          final image = await metricsBoundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('/tmp/maintenance-metrics-\${brightness.name}.png').writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        final fixed = MachineMaintenanceSnapshot({'platform': 'Linux',
          'memory': 'MemTotal: 31641540 kB\\nMemFree: 1226252 kB\\nMemAvailable: 18519936 kB\\nBuffers: 364560 kB\\nCached: 8512236 kB\\nSwapTotal: 8388608 kB\\nSwapFree: 7340032 kB\\nActive: 4256032 kB\\nInactive: 2460928 kB\\nSlab: 503360 kB',
          'pressure': '/proc/pressure/cpu\\nsome avg10=12.5 avg60=3.2 avg300=0.5 total=1200\\n/proc/pressure/memory\\nsome avg10=2.1 avg60=1.2 avg300=0.3 total=2100\\n/proc/pressure/io\\nfull avg10=5.4 avg60=2.3 avg300=1.2 total=3300',
          'capabilities': '可用工具: ps awk sed vmstat iostat',
        });
        await tester.pumpWidget(MaterialApp(locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(fontFamily: '运维预览字体', colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff526914), brightness: brightness)),
          home: Scaffold(body: RepaintBoundary(key: const ValueKey('固定指标预览'), child: ListView(padding: const EdgeInsets.all(24), children: [
            for (final section in ['memory', 'pressure', 'capabilities'])
              Padding(padding: const EdgeInsets.only(bottom: 12), child: _MaintenanceCard(title: _maintenanceSectionLabels[section] ?? section, scrollBody: false,
                child: _MaintenanceMetricContent(data: fixed, section: section))),
          ])))));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final fixedBoundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('固定指标预览')));
        await tester.runAsync(() async {
          final image = await fixedBoundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('/tmp/maintenance-fixed-\${brightness.name}.png').writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        await tester.pumpWidget(const SizedBox());
      }
      await tester.binding.setSurfaceSize(null);
    });
    return;
  }

  testWidgets('趋势窄窗口和大字体适配浅深主题', (tester) async {
    if (Platform.environment['MAINTENANCE_FONT'] != null) {
      await tester.runAsync(() async {
        await (FontLoader('运维预览字体')..addFont(File(Platform.environment['MAINTENANCE_FONT']!).readAsBytes().then((bytes) => ByteData.sublistView(bytes)))).load();
      });
    }
    for (final brightness in [Brightness.light, Brightness.dark]) {
      await tester.pumpWidget(MaterialApp(locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(fontFamily: Platform.environment['MAINTENANCE_FONT'] != null ? '运维预览字体' : null, colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal, brightness: brightness)),
        home: Scaffold(body: MediaQuery(data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: RepaintBoundary(key: const ValueKey('趋势预览'), child: SizedBox(width: 280, height: 190,
            child: _MaintenanceTrend(points: List.generate(30,
              (i) => (time: 1700000000000.0 + i * 3000, value: .45 + .25 * math.sin(i / 3))))))))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (Platform.environment['MAINTENANCE_TREND_PREVIEW'] != null) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('趋势预览')));
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('/tmp/maintenance-trend-\${brightness.name}.png').writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    }
    await tester.pumpWidget(const SizedBox());
  });

  test('系统摘要与跨平台连接解析保留时间和 IPv6 地址', () {
    final mac = MachineMaintenanceSnapshot({'platform': 'Darwin', 'system': 'ProductVersion: 27.0.1\\nDarwin host 27.0.0 Darwin Kernel Version 27.0.0: Tue 13:20:00', 'sockets': 'tcp46 0 0 *.80 *.* LISTEN\\nudp4 0 0 127.0.0.1.53 *.* 0', 'host': 'host'});
    expect(_maintenanceFacts(mac)['系统版本'], '27.0.1');
    expect(_maintenanceFacts(mac)['内核版本'], '27.0.0');
    expect(_maintenanceConnections(mac).first, ['TCP46', '*.80', '*.*', 'LISTEN', '0', '0', '—']);
    final linux = MachineMaintenanceSnapshot({'platform': 'Linux', 'sockets': 'tcp LISTEN 0 128 [::]:22 [::]:*'});
    expect(_maintenanceConnections(linux).single, ['TCP', '[::]:22', '[::]:*', 'LISTEN', '0', '128', '—']);
    final windows = MachineMaintenanceSnapshot({'platform': 'Windows', 'sockets': 'TCP [::1]:80 [::]:0 LISTENING 20'});
    expect(_maintenanceConnections(windows).single, ['TCP', '[::1]:80', '[::]:0', 'LISTENING', '—', '—', '20']);
  });

  testWidgets('扩展指标直接显示分页表格并区分累计值与缺失值', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 800));
    final data = MachineMaintenanceSnapshot({
      'platform': 'Linux',
      'disks': List.generate(35, (i) => 'disk\$i 20 0 4 8 30 0 6 9').join('\\n'),
    });
    await tester.pumpWidget(MaterialApp(locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: _MaintenanceCard(title: '磁盘累计计数', scrollBody: false,
        child: _MaintenanceMetricContent(data: data, section: 'disks')))));
    await tester.pumpAndSettle();
    expect(find.text('累计读取次数'), findsOneWidget);
    expect(find.text('disk0'), findsOneWidget);
    expect(find.byType(OpenHandOperationalRankTable), findsOneWidget);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.byType(SelectableText), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('固定指标完整展开、容量易读且窄屏无溢出', (tester) async {
    final data = MachineMaintenanceSnapshot({'platform': 'Linux',
      'memory': ['MemTotal: 31641540 kB', 'MemAvailable: 18519936 kB',
        ...List.generate(45, (i) => 'metric\$i: \${i + 1} kB')].join('\\n'),
      'pressure': '/proc/pressure/cpu\\nsome avg10=12.5 avg60=3.2 avg300=0.5 total=1200',
      'capabilities': '可用工具: ps awk sed',
    });
    for (final width in [360.0, 1280.0]) {
      await tester.binding.setSurfaceSize(Size(width, 1000));
      for (final brightness in [Brightness.light, Brightness.dark]) {
        await tester.pumpWidget(MaterialApp(locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(fontFamily: '运维预览字体', colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff526914), brightness: brightness)),
          home: Scaffold(body: RepaintBoundary(key: const ValueKey('固定指标预览'), child: SingleChildScrollView(
            child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
              for (final section in ['pressure', 'capabilities', 'memory'])
                _MaintenanceCard(title: section, scrollBody: false,
                  child: _MaintenanceMetricContent(data: data, section: section)),
            ])))))));
        await tester.pumpAndSettle();
        expect(find.byType(OpenHandOperationalRankTable), findsNothing);
        expect(find.text('30.2 GB'), findsOneWidget);
        expect(find.text('扩展指标：metric44'), findsOneWidget);
        expect(find.text('12.5%'), findsOneWidget);
        expect(find.byType(Chip), findsNWidgets(3));
        expect(tester.takeException(), isNull);

      }
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('四张指标卡均分父布局，窄屏按可用宽度换行', (tester) async {
    final data = MachineMaintenanceSnapshot({'platform': 'Darwin', 'memory': 'MemTotal: 33554432 kB\\nMemAvailable: 9835648 kB\\nSwapTotal: 0 kB\\nSwapFree: 0 kB'});
    for (final width in [1400.0, 600.0, 360.0]) {
      await tester.binding.setSurfaceSize(Size(width, 1000));
      await tester.pumpWidget(MaterialApp(locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: SingleChildScrollView(child: _MaintenanceCard(title: '内存详情', scrollBody: false,
          child: _MaintenanceMetricContent(data: data, section: 'memory'))))));
      await tester.pumpAndSettle();
      final grid = tester.widget<_MaintenanceGrid>(find.byType(_MaintenanceGrid).last);
      expect(grid.children.length, 4);
      final rects = [for (final child in grid.children) tester.getRect(find.byWidget(child))];
      final parent = tester.getRect(find.byType(_MaintenanceGrid).last);
      final columns = width == 1400 ? 4 : width == 600 ? 2 : 1;
      final expectedWidth = (parent.width - 12 * (columns - 1)) / columns;
      for (var i = 0; i < rects.length; i++) {
        expect(rects[i].width, closeTo(expectedWidth, .01));
        if (i % columns == 0) expect(rects[i].left, closeTo(parent.left, .01));
        if (i % columns == columns - 1) expect(rects[i].right, closeTo(parent.right, .01));
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('动态指标卡片随语言切换更新并保留原始标识', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 900));
    final data = MachineMaintenanceSnapshot({'platform': 'Linux',
      'vm': 'pgscan_direct_normal 2803403851\\nnr_active_anon 1234\\nthp_fault_alloc 20'});
    for (final locale in [const Locale('zh'), const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'), const Locale('en'), const Locale('fr'), const Locale('de'), const Locale('ja')]) {
      final l10n = lookupAppLocalizations(locale);
      await tester.pumpWidget(MaterialApp(locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: SingleChildScrollView(child: _MaintenanceMetricContent(data: data, section: 'vm')))));
      await tester.pumpAndSettle();
      expect(find.text(l10n.maintenanceCounterPgscan + ' · ' + l10n.maintenanceCounterDirect + ' · ' + l10n.maintenanceCounterNormal), findsOneWidget);
      expect(find.text('pgscan_direct_normal'), findsNothing);
      expect(find.byTooltip('pgscan_direct_normal · 2803403851 · —'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('数字切换保留精度、单位与刷新偏好并遵循减少动画', (tester) async {
    var raw = '9007199254740993';
    late StateSetter update;
    await tester.pumpWidget(MaterialApp(locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: StatefulBuilder(builder: (context, setState) {
        update = setState;
        return Scaffold(body: MediaQuery(data: const MediaQueryData(disableAnimations: true), child: Column(children: [
          _MaintenanceNumber(raw: raw),
          const _MaintenanceNumber(raw: '1500'),
          const _MaintenanceNumber(raw: '1536', unit: 'B'),
          const _MaintenanceNumber(raw: '3600000 ms'),
          const _MaintenanceNumber(raw: '—'),
          const _MaintenanceNumber(raw: 'NaN'),
          const _MaintenanceNumber(raw: '0'),
          const _MaintenanceNumber(raw: '-1500'),
        ])));
      })));
    await tester.pumpAndSettle();
    expect(find.text('1.5k'), findsOneWidget);
    expect(find.text('-1.5k'), findsOneWidget);
    expect(find.text('1 h'), findsOneWidget);
    expect(find.text('1.5 KB'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(find.text('NaN'), findsOneWidget);
    await tester.tap(find.text('1.5k'));
    await tester.pump();
    expect(find.text('1500'), findsOneWidget);
    await tester.tap(find.text('9P'));
    await tester.pump();
    expect(find.text('9007199254740993'), findsOneWidget);
    update(() => raw = '9007199254740995');
    await tester.pump();
    expect(find.text('9007199254740995'), findsOneWidget);
    await tester.tap(find.text('9007199254740995'));
    await tester.pump();
    expect(find.text('9P'), findsOneWidget);
    await tester.tap(find.text('1 h'));
    await tester.pump();
    expect(find.text('3600000 ms'), findsOneWidget);
    await tester.tap(find.text('1.5 KB'));
    await tester.pump();
    expect(find.text('1536 B'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('磁盘单元格可独立切换且进程标识不缩写', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    await tester.pumpWidget(MaterialApp(locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: _MaintenanceTable(
        headers: ['PID', '累计读取次数', '累计读取字节'],
        rows: [OpenHandOperationalRankRow(rowKey: 'disk', value: 0,
          cells: ['123456', '1500', '1536'])]))));
    await tester.pumpAndSettle();
    expect(find.text('123456'), findsOneWidget);
    expect(find.text('1.5k'), findsOneWidget);
    expect(find.text('1.5 KB'), findsOneWidget);
    await tester.tap(find.text('1.5k'));
    await tester.pump(const Duration(milliseconds: 30));
    expect(find.text('1500'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('1.5k'), findsNothing);
    expect(find.text('1.5 KB'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('列表长按反馈填满条目且不覆盖相邻行', (tester) async {
    for (final theme in [OpenHandTheme.light(OpenHandThemePreset.values.first), OpenHandTheme.dark(OpenHandThemePreset.values.first)]) {
      await tester.pumpWidget(MaterialApp(theme: theme, locale: const Locale('zh'), localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, home: Scaffold(body: Align(alignment: Alignment.topLeft,
        child: RepaintBoundary(key: const ValueKey('整行反馈'), child: SizedBox(width: 320,
          child: _MaintenanceCard(title: '诊断项目', contentPadding: EdgeInsets.zero, child: Column(children: [
            ListTile(title: const Text('第一行'), onTap: () {}),
            ListTile(title: const Text('第二行'), onTap: () {}),
          ]))))))));
      await tester.pumpAndSettle();
      final row = find.byType(ListTile).first;
      final ink = tester.widget<InkWell>(find.descendant(of: row, matching: find.byType(InkWell)));
      expect(ink.customBorder, const RoundedRectangleBorder());
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('整行反馈')));
      final origin = tester.getTopLeft(find.byKey(const ValueKey('整行反馈')));
      final rowRect = tester.getRect(row).shift(-origin);
      final otherRect = tester.getRect(find.byType(ListTile).last).shift(-origin);
      expect(rowRect.left, 1);
      expect(rowRect.right, 319);
      Future<List<int>> colors() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        final points = [Offset(3, rowRect.top + 3), Offset(316, rowRect.top + 3), Offset(3, otherRect.top + 3)];
        final values = [for (final p in points) bytes.getUint32((p.dy.toInt() * image.width + p.dx.toInt()) * 4)];
        image.dispose();
        return values;
      }
      final before = (await tester.runAsync(colors))!;
      final gesture = await tester.startGesture(tester.getCenter(row));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 700));
      final pressed = (await tester.runAsync(colors))!;
      expect(pressed[0], isNot(before[0]));
      expect(pressed[1], isNot(before[1]));
      expect(pressed[2], before[2]);
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(await tester.runAsync(colors), before);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('共用卡片悬停无阴影遮罩，按压仍有反馈', (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child:
      OpenHandOpsPressScale(tone: Colors.blue, onTap: () => taps++, child:
        const SizedBox(width: 240, height: 100, child: Text('卡片')))))));
    final card = find.byType(OpenHandOpsPressScale);
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(card));
    await tester.pumpAndSettle();
    BoxDecoration decoration() => tester.widget<AnimatedContainer>(find.descendant(
      of: card, matching: find.byType(AnimatedContainer))).decoration! as BoxDecoration;
    expect(decoration().color!.a, 0);
    expect(decoration().boxShadow, isNull);
    final press = await tester.startGesture(tester.getCenter(card));
    await tester.pumpAndSettle();
    expect(decoration().color!.a, greaterThan(0));
    await press.up();
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(decoration().color!.a, 0);
    await mouse.removePointer();
    expect(tester.takeException(), isNull);
  });

  testWidgets('浅深主题条目与输入框无悬停底色且保留点击和焦点反馈', (tester) async {
    for (final theme in [OpenHandTheme.light(OpenHandThemePreset.values.first), OpenHandTheme.dark(OpenHandThemePreset.values.first)]) {
      var taps = 0;
      final focus = FocusNode();
      await tester.pumpWidget(MaterialApp(theme: theme, home: Scaffold(body: Column(children: [
        ListTile(title: const Text('诊断条目'), onTap: () => taps++),
        TextField(focusNode: focus),
      ]))));
      expect(theme.hoverColor, Colors.transparent);
      expect(theme.inputDecorationTheme.hoverColor, Colors.transparent);
      expect(theme.focusColor.a, greaterThan(0));
      final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.text('诊断条目')));
      await tester.pumpAndSettle();
      final ink = tester.widget<InkWell>(find.descendant(of: find.byType(ListTile), matching: find.byType(InkWell)));
      expect(ink.hoverColor ?? theme.hoverColor, Colors.transparent);
      await tester.tap(find.text('诊断条目'));
      expect(taps, 1);
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(focus.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox());
      focus.dispose();
    }
  });

  testWidgets('六种语言切换覆盖标签、状态与原始数据边界', (tester) async {
    final service = _MaintenanceFixture();
    for (final width in [1180.0, 580.0]) {
    await tester.binding.setSurfaceSize(Size(width, 900));
    for (final locale in [const Locale('zh'), const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'), const Locale('en'), const Locale('fr'), const Locale('de'), const Locale('ja')]) {
      final l10n = lookupAppLocalizations(locale);
      await tester.pumpWidget(ChangeNotifierProvider<MachineTerminalFileService>.value(value: service,
        child: MaterialApp(locale: locale, localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: _MachineMaintenanceDialog(sessionId: '会话', terminalId: '终端')))));
      await tester.pumpAndSettle();
      expect(find.text(l10n.maintenanceCenter), findsOneWidget);
      await tester.ensureVisible(find.text(l10n.maintenanceOverview));
      await tester.tap(find.text(l10n.maintenanceOverview));
      await tester.pumpAndSettle();
      expect(find.text(l10n.maintenanceBasicInfo), findsOneWidget);
      expect(find.text('测试服务器'), findsWidgets);
      final context = tester.element(find.byType(_MachineMaintenanceDialog));
      expect(maintenanceLabel(context, 'LISTENING'), l10n.maintenanceListening);
      expect(maintenanceLabel(context, 'Running'), l10n.maintenanceRunning);
      expect(maintenanceLabel(context, 'ProductVersion'), l10n.maintenanceProductVersion);
      for (final field in [
        'pgalloc_dma32', 'pgalloc_normal', 'pgalloc_movable', 'pgfree', 'pgactivate',
        'pgdeactivate', 'pgfault', 'pgmajfault', 'pglazyfreed', 'pgrefill_dma',
        'pgrefill_dma32', 'pgrefill_normal', 'pgrefill_movable', 'pgsteal_kswapd_dma',
        'pgsteal_kswapd_dma32', 'pgsteal_kswapd_normal', 'pgsteal_direct_normal',
        'pgscan_direct_throttle', 'nr_active_anon', 'Active(file)', 'SwapCached',
        'HugePages_Total', 'workingset_refault_file', 'thp_fault_alloc',
        'PageReadsPersec', 'PoolPagedBytes',
      ]) {
        final translated = maintenanceMetricLabel(context, field, '名称', section: 'vm');
        expect(translated, isNot(field), reason: field);
        expect(translated, isNot(contains(field)), reason: '已知指标应有语义翻译：' + field);
        expect(translated, isNot(contains('null')));
      }
      expect(maintenanceMetricLabel(context, 'pgscan_direct_normal', '名称'),
        l10n.maintenanceCounterPgscan + ' · ' + l10n.maintenanceCounterDirect + ' · ' + l10n.maintenanceCounterNormal);
      expect(maintenanceMetricLabel(context, '文件上限', '名称', section: 'kernel'), l10n.maintenanceMetricFileLimit);
      expect(maintenanceMetricLabel(context, 'vendor_new_counter', '名称', section: 'vm'),
        l10n.maintenanceExtendedMetric('vendor_new_counter'));
      expect(maintenanceMetricLabel(context, '/dev/sda1', '名称', section: 'blocks'), '/dev/sda1');
      expect(maintenanceMetricLabel(context, 'pgfault', '数值'), 'pgfault');
      expect(maintenanceMetricLabel(context, '10.0.0.1', '地址'), '10.0.0.1');

      const raw = 'ProductVersion: 27.0.1\\nnameserver[0] : 2001:db8::1\\nCommandLine: /bin/Name --host=State\\nlog: ProductVersion: original';
      final translated = maintenanceLocalizedOutput(context, raw);
      expect(translated, contains(l10n.maintenanceProductVersion));
      expect(translated, contains('2001:db8::1'));
      expect(translated, contains('/bin/Name --host=State'));
      expect(translated, contains('log: ProductVersion: original'));
      for (final label in [l10n.maintenanceProcesses, l10n.maintenanceServices, l10n.maintenanceNetworkDiagnostics]) {
        await tester.ensureVisible(find.text(label));
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      expect(tester.takeException(), isNull);
    }
    }
    await tester.pumpWidget(MaterialApp(locale: const Locale('zh'), localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: _MaintenanceReadout(text: 'ProductVersion: 27.0.1'))));
    await tester.pumpAndSettle();
    expect(find.text('产品版本'), findsOneWidget);
    expect(find.text('27.0.1'), findsOneWidget);
    expect(find.text('原始输出'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('二级详情结构化展示适配窄窗口与六种语言', (tester) async {
    final fixtures = <String, String>{
      'startup': '/Library/LaunchAgents:\\ncom.example.agent.plist\\n/Users/test/Library/LaunchAgents:\\nMy Agent.plist',
      'users': 'root pts/7 Sep 29 16:27 (host.example)',
      'dns': '# comment\\nnameserver 2001:db8::1',
      'status': 'Name: worker\\nRestart=no\\nExecStart=/bin/app --value=a=b',
      'io': 'read_bytes: 5195840788075',
      'logs': '-- No entries --',
      'containers': 'CONTAINER ID  IMAGE         COMMAND          STATUS       PORTS       NAMES\\nabc           app:latest    "sh -c hello"    Up 2 hours               worker',
    };
    for (final locale in AppLocalizations.supportedLocales) {
      await tester.binding.setSurfaceSize(const Size(480, 900));
      for (final fixture in fixtures.entries) {
        await tester.pumpWidget(MaterialApp(locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: SingleChildScrollView(child: _MaintenanceReadout(
            text: fixture.value, section: fixture.key)))));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('原始输出'), findsNothing);
        if (fixture.key == 'startup') {
          final l10n = AppLocalizations.of(tester.element(find.byType(_MaintenanceReadout)))!;
          expect(find.text(l10n.maintenanceStartupSystemAgent), findsOneWidget);
          expect(find.text('com.example.agent.plist'), findsOneWidget);
        }
      }
    }
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
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
          child: MaterialApp(locale: const Locale('zh'), localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, theme: ThemeData(fontFamily: font == null ? null : '运维预览字体', colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal, brightness: brightness)),
            home: MediaQuery(data: MediaQueryData(size: Size(width, 900), textScaler: TextScaler.linear(width == 580 ? 1.5 : 1)),
              child: const Scaffold(body: RepaintBoundary(key: ValueKey('运维预览'), child: _MachineMaintenanceDialog(sessionId: '会话', terminalId: '终端')))))));
        await tester.pumpAndSettle();
        for (final label in ['进程管理', '系统服务', '网络与诊断', '运行总览']) {
          await tester.ensureVisible(find.text(label));
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
            expect(find.byTooltip('终止进程'), findsOneWidget);
            await tester.tap(find.byTooltip('关闭').last);
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
        child: const MaterialApp(locale: const Locale('zh'), localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, home: Scaffold(body: _MachineMaintenanceDialog(sessionId: '会话', terminalId: '终端')))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('进程管理'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('测试进程'));
      await tester.tap(find.text('测试进程'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('终止进程'), findsOneWidget);
      expect(find.byTooltip('暂停进程'), target.\$1 == 'Darwin' ? findsOneWidget : findsNothing);
      await tester.tap(find.byTooltip('关闭').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('系统服务'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('nginx.service').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('nginx.service').first);
      await tester.pumpAndSettle();
      expect(find.byTooltip('启动服务'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('全局胶囊主题下运维输入框各状态保持圆角矩形', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    final service = _MaintenanceFixture();
    for (final brightness in [Brightness.light, Brightness.dark]) {
      const capsule = OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(999)));
      await tester.pumpWidget(ChangeNotifierProvider<MachineTerminalFileService>.value(value: service,
        child: MaterialApp(locale: const Locale('zh'), localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(brightness: brightness, inputDecorationTheme: const InputDecorationTheme(
            border: capsule, enabledBorder: capsule, disabledBorder: capsule,
            focusedBorder: capsule, errorBorder: capsule, focusedErrorBorder: capsule)),
          home: const Scaffold(body: _MachineMaintenanceDialog(sessionId: '会话', terminalId: '终端')))));
      await tester.pumpAndSettle();
      for (final label in ['进程管理', '系统服务']) {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        final field = find.byWidgetPredicate((widget) => widget is TextField && widget.decoration?.hintText != null);
        await tester.ensureVisible(field);
        await tester.tap(field);
        await tester.pumpAndSettle();
        final decorator = tester.widget<InputDecorator>(find.descendant(of: field, matching: find.byType(InputDecorator)));
        expect(decorator.isFocused, isTrue);
        final decoration = decorator.decoration.applyDefaults(Theme.of(tester.element(field)).inputDecorationTheme);
        for (final border in [decoration.border, decoration.enabledBorder, decoration.disabledBorder,
          decoration.focusedBorder, decoration.errorBorder, decoration.focusedErrorBorder]) {
          expect(border, isA<OutlineInputBorder>());
          expect((border! as OutlineInputBorder).borderRadius, BorderRadius.circular(10));
        }
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('进程表使用剩余高度，移除数量卡片并将排序靠右', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1100));
    final service = _MaintenanceFixture();
    await tester.pumpWidget(ChangeNotifierProvider<MachineTerminalFileService>.value(value: service,
      child: const MaterialApp(locale: Locale('zh'), localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(data: MediaQueryData(size: Size(1440, 1100)), child: Scaffold(body: _MachineMaintenanceDialog(sessionId: '会话', terminalId: '终端'))))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('进程管理'));
    await tester.pumpAndSettle();
    expect(find.text('bash 5.2'), findsOneWidget);
    final workers = find.byWidgetPredicate((w) => w is _MaintenanceToolbarMenu<int> && w.icon == Icons.account_tree_outlined);
    final toolbarGap = tester.getRect(find.byType(_MachineTerminalIconButton).first).left - tester.getRect(workers).right;
    expect(toolbarGap, inInclusiveRange(0, 14));
    expect(find.text('手动刷新'), findsNothing);
    expect(find.textContaining('更新于'), findsNothing);
    expect(find.text('上一批进程'), findsNothing);
    expect(find.text('下一批进程'), findsNothing);
    final table = tester.widget<_MaintenanceTable>(find.byType(_MaintenanceTable).first);
    expect(table.limitToViewport, isFalse);
    expect(table.headers, containsAll(['父进程 ID', '优先级', '虚拟内存', '累计 CPU 时间']));
    expect(table.maxBodyHeight, greaterThan(1100 * .45));
    final dialogBottom = tester.getRect(find.descendant(of: find.byType(Dialog).first, matching: find.byType(Column)).first).bottom;
    expect(tester.getRect(find.byKey(const ValueKey('运维进程列表'))).bottom, closeTo(dialogBottom - _maintenancePanelBottomInset, 1));
    final summary = find.byWidgetPredicate((w) => w is _MaintenanceToolbarMenu<int> && w.icon == Icons.filter_list_rounded);
    final search = find.byType(TextField).first;
    final controlHeight = tester.getSize(find.byType(_MachineTerminalIconButton).first).height;
    expect(tester.getSize(search).height, controlHeight);
    expect(summary, findsNothing);
    final sortMenu = find.byWidgetPredicate((w) => w is _MaintenanceToolbarMenu<int> && w.label == 'CPU 降序');
    expect(tester.getSize(sortMenu).height, controlHeight);
    expect(tester.widget<OpenHandOperationalRankTable>(find.byType(OpenHandOperationalRankTable).first).compact, isTrue);
    expect(tester.widget<OpenHandTablePagination>(find.byType(OpenHandTablePagination).first).controlHeight, controlHeight);
    expect(tester.getRect(sortMenu).left, greaterThan(tester.getRect(search).right));
    expect(tester.getRect(sortMenu).right, closeTo(tester.getRect(find.byKey(const ValueKey('运维进程列表'))).right, 1));
    for (final tab in ['运行总览', '系统服务', '网络与诊断']) {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
      if (tab == '系统服务') {
        final services = tester.widget<_MaintenanceTable>(find.byType(_MaintenanceTable).first);
        expect(services.headers.length, 12);
        expect(services.rows.first.cells.skip(6).toList(), ['42', '1 MB', '2.00 s', '3', '0', '0']);
        expect(tester.getSize(find.byType(TextField).first).height, controlHeight);
        for (final label in ['开机启动状态', '系统定时器']) {
          final button = find.widgetWithText(OutlinedButton, label);
          if (button.evaluate().isNotEmpty) expect(tester.getSize(button).height, controlHeight);
        }
      }
      final viewport = find.byType(ListView).first;
      expect(tester.getRect(viewport).bottom, closeTo(dialogBottom - _maintenancePanelBottomInset, 1));
      await tester.drag(viewport, const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(tester.getRect(viewport).bottom, closeTo(dialogBottom - _maintenancePanelBottomInset, 1));
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('二级弹窗操作靠右等高，加载后按内容收拢', (tester) async {
    for (final width in [1100.0, 580.0]) {
      for (final actions in [
        {'终止进程': 'stop', '暂停进程': 'pause', '恢复进程': 'resume'},
        {'启用开机启动': 'enable', '禁用开机启动': 'disable'},
        {'启动服务': 'start', '停止服务': 'stop', '重启服务': 'restart', '自动启动': 'auto', '手动启动': 'manual', '禁用服务': 'disable'},
      ]) {
        await tester.binding.setSurfaceSize(Size(width, 850));
        final pending = Completer<String>();
        await tester.pumpWidget(MaterialApp(locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MediaQuery(data: MediaQueryData(size: Size(width, 850), textScaler: TextScaler.linear(width < 600 ? 1.5 : 1)),
            child: Scaffold(body: _MachineMaintenanceDetails(title: '很长的进程或服务名称 /usr/libexec/remoted',
              load: () => pending.future, execute: (_) async => '', actions: actions)))));
        await tester.pump();
        final header = find.byType(_MachineTerminalDialogHeader);
        final refresh = find.byTooltip('刷新详情');
        final progress = find.byType(LinearProgressIndicator);
        final headerRect = tester.getRect(header);
        final refreshRect = tester.getRect(refresh);
        final progressRect = tester.getRect(progress);
        for (final label in actions.keys) {
          final button = find.byWidgetPredicate((widget) => widget is _MachineTerminalIconButton && widget.tooltip == label);
          final rect = tester.getRect(button);
          expect(rect.size, const Size(34, 34));
          expect(rect.right, lessThan(refreshRect.left));
          expect(rect.bottom, lessThan(headerRect.bottom));
          expect(tester.widget<_MachineTerminalIconButton>(button).onPressed, isNull);
        }
        expect(find.byType(OutlinedButton), findsNothing);
        expect(progressRect.top, greaterThan(headerRect.bottom));
        expect(progressRect.left, greaterThan(headerRect.left));
        expect(tester.takeException(), isNull);
        pending.complete('__OH_OPS_platform__\\nLinux\\n__OH_OPS_end__\\n');
        await tester.pumpAndSettle();
        expect(tester.getSize(header), headerRect.size);
        expect(tester.getSize(find.descendant(of: find.byType(Dialog), matching: find.byType(Column)).first).height, lessThan(850 * .82));
        expect(find.byType(LinearProgressIndicator), findsNothing);
        for (final label in actions.keys) {
          expect(tester.widget<_MachineTerminalIconButton>(find.byWidgetPredicate((widget) => widget is _MachineTerminalIconButton && widget.tooltip == label)).onPressed, isNotNull);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    }
    await tester.binding.setSurfaceSize(null);
  });


  testWidgets('采集详情按内容收拢且长内容不越过最大高度', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    final service = _MaintenanceFixture();
    await tester.pumpWidget(ChangeNotifierProvider<MachineTerminalFileService>.value(
      value: service,
      child: const MaterialApp(locale: Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: _MachineMaintenanceDialog(sessionId: '会话', terminalId: '终端')))));
    await tester.pumpAndSettle();
    final state = tester.state<_MachineMaintenanceDialogState>(find.byType(_MachineMaintenanceDialog));
    for (final text in ['', '单条记录', List.filled(100, '这是一条完整的日志记录').join('\\n')]) {
      final closed = state._showCollected('最近日志', text);
      await tester.pumpAndSettle();
      final dialog = find.byType(Dialog).last;
      final rect = tester.getRect(find.descendant(of: dialog, matching: find.byType(Column)).first);
      expect(rect.height, lessThanOrEqualTo(900 * .7));
      if (text.length < 100) {
        expect(rect.height, lessThan(400));
      } else {
        final scrollables = tester.stateList<ScrollableState>(
          find.descendant(of: dialog, matching: find.byType(Scrollable)));
        final scrolling = scrollables.where((state) => state.position.maxScrollExtent > 0);
        expect(scrolling, isNotEmpty);
        for (final scroll in scrolling) {
          scroll.position.jumpTo(scroll.position.maxScrollExtent);
        }
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      Navigator.of(tester.element(dialog)).pop();
      await tester.pumpAndSettle();
      await closed;
    }
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });


  testWidgets('关系树处理循环孤儿搜索并保留展开状态与详情操作', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 900));
    var tapped = '';
    final rows = [
      for (final id in ['1', '2', '3', '4'])
        OpenHandOperationalRankRow(value: 0, cells: [id, '进程\$id', '运行中']),
    ];
    Widget host(String query) => MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: _MaintenanceBrowser(
        query: query, nameColumn: 1,
        parents: const {'1': ['3'], '2': ['1'], '3': ['2'], '4': ['999']},
        table: _MaintenanceTable(headers: const ['PID', '进程', '状态'], rows: rows,
          onRowTap: (row) => tapped = row.cells.first))));
    await tester.pumpWidget(host(''));
    await tester.pumpAndSettle();
    await tester.tap(find.text('关系树'));
    await tester.pumpAndSettle();
    for (final id in ['1', '2', '3', '4']) expect(find.text('进程\$id'), findsOneWidget);
    await tester.tap(find.byTooltip('收起').first);
    await tester.pumpAndSettle();
    expect(find.byTooltip('展开'), findsOneWidget);
    await tester.pumpWidget(host('进程2'));
    await tester.pumpAndSettle();
    expect(find.text('进程2'), findsOneWidget);
    expect(find.text('进程1'), findsOneWidget);
    expect(find.text('进程4'), findsNothing);
    await tester.tap(find.text('进程2'));
    expect(tapped, '2');
    await tester.pumpWidget(host(''));
    await tester.pumpAndSettle();
    expect(find.byTooltip('展开'), findsOneWidget);
    await tester.tap(find.text('列表'));
    await tester.pumpAndSettle();
    expect(find.byType(_MaintenanceTable), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });


  testWidgets('树形按钮保持方形，双卡填满列宽，错列卡片紧接前项', (tester) async {
    await tester.runAsync(() async {
      for (final entry in {'运维预览字体': Platform.environment['MAINTENANCE_FONT'], 'MaterialIcons': Platform.environment['MAINTENANCE_ICONS']}.entries) {
        if (entry.value != null) await (FontLoader(entry.key)..addFont(File(entry.value!).readAsBytes().then((bytes) => ByteData.sublistView(bytes)))).load();
      }
    });
    await tester.binding.setSurfaceSize(const Size(1100, 850));
    await tester.pumpWidget(MaterialApp(locale: const Locale('zh'), localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales, theme: OpenHandTheme.light(OpenHandThemePreset.values.first).copyWith(textTheme: OpenHandTheme.light(OpenHandThemePreset.values.first).textTheme.apply(fontFamily: Platform.environment['MAINTENANCE_FONT'] == null ? null : '运维预览字体')),
      home: Scaffold(body: RepaintBoundary(key: const ValueKey('树预览'), child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
        _MaintenanceGrid(children: [Container(key: const ValueKey('甲'), height: 40), Container(key: const ValueKey('乙'), height: 40)]),
        _MaintenanceGrid(staggered: true, maxColumns: 2, children: [SizedBox(key: const ValueKey('长卡'), height: 100), SizedBox(key: const ValueKey('短卡'), height: 30), SizedBox(height: 10), SizedBox(key: const ValueKey('续卡'), height: 10)]),
        _MaintenanceBrowser(query: '', nameColumn: 1, parents: const {'2': ['1'], '3': ['2']},
          table: _MaintenanceTable(maxBodyHeight: 450, headers: const ['PID', '进程', '状态', 'CPU', '内存'], rows: [
            OpenHandOperationalRankRow(value: 0, cells: ['1', 'launchd', '运行', '1%', '20 MB']),
            OpenHandOperationalRankRow(value: 0, cells: ['2', '应用进程', '运行', '2%', '120 MB']),
            OpenHandOperationalRankRow(value: 0, cells: ['3', '后台工作进程', '休眠', '0%', '12 MB']),
          ])),
      ]))))));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const ValueKey('甲'))).width, 528);
    expect(tester.getRect(find.byKey(const ValueKey('续卡'))).top - tester.getRect(find.byKey(const ValueKey('短卡'))).bottom, 12);
    await tester.tap(find.text('关系树'));
    await tester.pumpAndSettle();
    for (final button in find.byType(IconButton).evaluate()) {
      final size = tester.getSize(find.byWidget(button.widget));
      expect(size.width, 32);
      expect(size.height, 32);
    }
    expect(tester.getTopLeft(find.text('后台工作进程')).dx, greaterThan(tester.getTopLeft(find.text('应用进程')).dx));
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('树预览')));
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('/tmp/maintenance-tree-preview.png').writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('服务名称分组适配六种语言窄窗口，节点可展开且保留完整名称', (tester) async {
    await tester.binding.setSurfaceSize(const Size(380, 700));
    for (final locale in [const Locale('zh'), const Locale('zh', 'Hant'), const Locale('en'), const Locale('de'), const Locale('fr'), const Locale('ja')]) {
      await tester.pumpWidget(MaterialApp(
        locale: locale, localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: _MaintenanceBrowser(query: '', parents: const {}, groupNames: true,
          table: _MaintenanceTable(headers: const ['名称', '状态', 'PID'], rows: [
            OpenHandOperationalRankRow(value: 0, cells: ['com.apple.test', 'running', '123']),
            OpenHandOperationalRankRow(value: 0, cells: ['com.apple.worker', 'stopped', '—']),
          ])))));
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(_MaintenanceBrowser));
      final l10n = AppLocalizations.of(context)!;
      final modes = find.byType(SegmentedButton<bool>);
      expect(tester.getTopLeft(modes).dx, 0);
      expect(tester.getSize(modes).height, greaterThanOrEqualTo(34));
      expect(maintenanceDetailLabel(context, 'Label'), l10n.maintenanceName);
      expect(maintenanceLabel(context, 'Label'), l10n.maintenanceName);
      expect(maintenanceDetailLabel(context, 'WorkingDirectory'), l10n.cronsWorkingDirectory);
      expect(maintenanceDetailLabel(context, 'GroupName'), l10n.maintenanceAccountGroup);
      await tester.tap(find.text(l10n.maintenanceNameTree));
      await tester.pumpAndSettle();
      expect(find.text('com.apple'), findsOneWidget);
      expect(find.text('com.apple.test'), findsOneWidget);
      await tester.tap(find.byTooltip(l10n.maintenanceTreeCollapse));
      await tester.pumpAndSettle();
      expect(find.text('com.apple.test'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
    await tester.binding.setSurfaceSize(null);
  });


  testWidgets('Apple GPU 首次采样不占空趋势框，容量保持单位且详情分栏', (tester) async {
    final service = _MaintenanceFixture()..platform = 'Darwin';
    service.gpuOutput = ['__OH_OPS_platform__', 'Darwin', '__OH_OPS_host__', 'GPU主机',
      '__OH_OPS_gpu_apple__', jsonEncode({'SPDisplaysDataType': [{'sppci_model': 'Apple M4', 'sppci_cores': '10', 'spdisplays_vendor': 'Apple', 'sppci_bus': 'builtin'}]}),
      '__OH_OPS_gpu_accelerators__', '+-o GPU "model" = "Apple M4" "Device Utilization %"=49 "Renderer Utilization %"=48 "In use system memory"=1053818880', '__OH_OPS_end__'].join('\\n');
    await tester.binding.setSurfaceSize(const Size(1440, 1100));
    await tester.pumpWidget(ChangeNotifierProvider<MachineTerminalFileService>.value(value: service,
      child: MaterialApp(builder: (context, child) => LayoutBuilder(builder: (context, constraints) => MediaQuery(data: MediaQuery.of(context).copyWith(size: constraints.biggest), child: child!)), theme: ThemeData(fontFamily: Platform.environment['MAINTENANCE_FONT'] == null ? null : '运维预览字体'), locale: Locale('zh'), localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales, home: const Scaffold(body: RepaintBoundary(key: ValueKey('GPU预览'), child: _MachineMaintenanceDialog(sessionId: '会话', terminalId: '终端'))))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('GPU 管理'));
    await tester.pumpAndSettle();
    expect(find.text('Apple M4'), findsOneWidget);
    expect(find.text('GPU 利用率趋势'), findsNothing);
    final facts = find.byType(_MaintenanceFacts);
    expect(facts, findsNWidgets(2));
    expect(tester.getRect(facts.first).top, tester.getRect(facts.last).top);
    expect(tester.getRect(facts.last).right, greaterThan(1200));
    expect(find.byIcon(Icons.memory_rounded), findsWidgets);
    await tester.tap(find.byTooltip('刷新当前分区'));
    await tester.pumpAndSettle();
    expect(find.byType(_MaintenanceTrend), findsOneWidget);
    if (Platform.environment['MAINTENANCE_FONT'] != null) {
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('GPU预览')));
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('/tmp/maintenance-gpu-preview.png').writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.binding.setSurfaceSize(const Size(420, 900));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: _MaintenanceNumber(raw: '1005 MB'))));
    await tester.pumpAndSettle();
    expect(find.text('1005 MB'), findsOneWidget);
    expect(find.text('1k MB'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('GPU 组件在未发现显卡时仍可展开查看安装元数据', (tester) async {
    await tester.binding.setSurfaceSize(const Size(520, 900));
    final service = _MaintenanceFixture();
    service.gpuOutput = ['__OH_OPS_platform__', 'Linux', '__OH_OPS_host__', 'GPU主机',
      '__OH_OPS_gpu_stack__', 'CUDA Toolkit\\tversion\\t12.8', 'cuDNN\\tversion\\t9.8',
      '__OH_OPS_gpu_fabric__', 'LoadState=not-found', '__OH_OPS_end__'].join('\\n');
    await tester.pumpWidget(ChangeNotifierProvider<MachineTerminalFileService>.value(value: service,
      child: MaterialApp(locale: const Locale('zh'), localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => LayoutBuilder(builder: (context, constraints) => MediaQuery(data: MediaQuery.of(context).copyWith(size: constraints.biggest), child: child!)),
        home: const Scaffold(body: _MachineMaintenanceDialog(sessionId: '会话', terminalId: '终端')))));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('GPU 管理'));
    await tester.tap(find.text('GPU 管理'));
    await tester.pumpAndSettle();
    expect(find.text('CUDA Toolkit'), findsOneWidget);
    await tester.tap(find.text('CUDA Toolkit'));
    await tester.pumpAndSettle();
    expect(find.text('12.8'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('GPU 分区按需采集并显示指标、显存图与连续趋势', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1100));
    final service = _MaintenanceFixture();
    await tester.pumpWidget(ChangeNotifierProvider<MachineTerminalFileService>.value(value: service,
      child: const MaterialApp(locale: Locale('zh'), localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: _MachineMaintenanceDialog(sessionId: '会话', terminalId: '终端')))));
    await tester.pumpAndSettle();
    expect(service.lastCommand, isNot(contains('section gpu_nvidia')));
    await tester.tap(find.text('GPU 管理'));
    await tester.pumpAndSettle();
    expect(service.lastCommand, contains('section gpu_nvidia'));
    expect(find.text('NVIDIA Test'), findsOneWidget);
    expect(find.text('45%'), findsWidgets);
    expect(find.text('80.5 W'), findsWidgets);
    await tester.tap(find.byTooltip('刷新当前分区'));
    await tester.pumpAndSettle();
    expect(find.byType(_MaintenanceTrend), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.binding.setSurfaceSize(const Size(520, 900));
    for (final locale in [const Locale('zh'), const Locale('zh', 'Hant'), const Locale('en'), const Locale('de'), const Locale('fr'), const Locale('ja')]) {
      await tester.pumpWidget(ChangeNotifierProvider<MachineTerminalFileService>.value(value: service,
        child: MaterialApp(locale: locale, localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: _MachineMaintenanceDialog(sessionId: '会话', terminalId: '终端')))));
      await tester.pumpAndSettle();
      expect(find.text('NVIDIA Test'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('首次加载与分区加载仅显示居中进度，刷新保留已有数据', (tester) async {
    final service = _MaintenanceFixture()..pending = Completer<String>();
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    await tester.pumpWidget(ChangeNotifierProvider<MachineTerminalFileService>.value(value: service,
      child: const MaterialApp(locale: Locale('zh'), localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: _MachineMaintenanceDialog(sessionId: '会话', terminalId: '终端')))));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(_MaintenanceCard), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('等待目标机器数据'), findsNothing);
    const sample = '__OH_OPS_platform__\\nLinux\\n__OH_OPS_host__\\n测试服务器\\n__OH_OPS_end__\\n';
    service.pending!.complete(sample);
    service.pending = null;
    await tester.pumpAndSettle();
    expect(find.text('基本信息'), findsOneWidget);
    service.pending = Completer<String>();
    await tester.tap(find.byTooltip('刷新当前分区'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('基本信息'), findsOneWidget);
    service.pending!.complete(sample);
    await tester.pumpAndSettle();
    for (final label in ['进程管理', '系统服务', '网络与诊断']) {
      service.pending = Completer<String>();
      await tester.tap(find.text(label));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(_MaintenanceCard), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      service.pending!.complete(sample);
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('首次失败显示简洁错误状态并支持重新采集', (tester) async {
    final service = _MaintenanceFixture()..fail = true;
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    await tester.pumpWidget(ChangeNotifierProvider<MachineTerminalFileService>.value(value: service,
      child: const MaterialApp(locale: const Locale('zh'), localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, home: Scaffold(body: _MachineMaintenanceDialog(sessionId: '会话', terminalId: '终端')))));
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

  testWidgets('重复行标识刷新、缩页与关闭弹窗不破坏列表索引', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    await tester.pumpWidget(MaterialApp(locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(builder: (context) => Scaffold(body: TextButton(
        onPressed: () => showAnimatedDialog<void>(context: context, builder: (context) {
          var revision = 0;
          return StatefulBuilder(builder: (context, update) => Dialog(child: SizedBox(width: 650, height: 450,
            child: Column(children: [
              TextButton(onPressed: () => update(() => revision++), child: const Text('更新重复行')),
              OpenHandOperationalRankTable(headers: const ['名称', '数值'],
                sortByValue: false, animateCellChanges: true,
                maxBodyHeight: 220, rows: List.generate(revision > 1 ? 4 : 20, (i) => OpenHandOperationalRankRow(
                  rowKey: i.isEven ? '重复标识' : null,
                  cells: ['相同名称', '\$revision-\$i'], value: 0))),
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('关闭测试弹窗')),
            ]))));
        }), child: const Text('打开测试弹窗'))))));
    await tester.tap(find.text('打开测试弹窗'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text('更新重复行'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.text('关闭测试弹窗'));
    await tester.pumpAndSettle();
    expect(find.text('关闭测试弹窗'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('运维公共表格支持页码、条数、跳页和刷新缩页', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    var count = 55;
    late StateSetter update;
    await tester.pumpWidget(MaterialApp(locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: StatefulBuilder(builder: (context, setState) {
        update = setState;
        return _MaintenanceTable(headers: const ['名称'], rows: [for (var i = 0; i < count; i++)
          OpenHandOperationalRankRow(value: i, rowKey: i, cells: ['设备-\$i'])]);
      }))));
    await tester.pumpAndSettle();
    expect(find.byType(OpenHandOperationalRankTable), findsOneWidget);
    expect(find.byType(DataTable), findsNothing);
    expect(tester.widget<OpenHandTablePagination>(find.byType(OpenHandTablePagination)).pageSize, 20);
    await tester.tap(find.byTooltip('下一页'));
    await tester.pumpAndSettle();
    expect(find.text('设备-20'), findsOneWidget);
    expect(find.text('设备-0'), findsNothing);
    await tester.enterText(find.byType(TextField), '3');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();
    expect(find.text('设备-40'), findsOneWidget);
    update(() {});
    await tester.pumpAndSettle();
    expect(tester.widget<OpenHandTablePagination>(find.byType(OpenHandTablePagination)).page, 3);
    update(() => count = 21);
    await tester.pumpAndSettle();
    expect(tester.widget<OpenHandTablePagination>(find.byType(OpenHandTablePagination)).page, 2);
    await tester.tap(find.text('20 条/页'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10 条/页').last);
    await tester.pumpAndSettle();
    final pager = tester.widget<OpenHandTablePagination>(find.byType(OpenHandTablePagination));
    expect(pager.pageSize, 10);
    expect(pager.page, 1);
    update(() => count = 0);
    await tester.pumpAndSettle();
    expect(find.text('暂无可用数据'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('表格只更新变化单元格，减少动画立即应用新值', (tester) async {
    var value = '10';
    var reduced = false;
    final builds = [0, 0];
    late StateSetter update;
    await tester.pumpWidget(MaterialApp(locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: StatefulBuilder(builder: (context, setState) {
        update = setState;
        return MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
          child: _MaintenanceTable(headers: const ['名称', '数值'], rows: [
            OpenHandOperationalRankRow(value: 0, rowKey: '设备', cells: ['设备', value], cellWidgets: [
              Builder(builder: (_) { builds[0]++; return const Text('设备'); }),
              Builder(builder: (_) { builds[1]++; return Text(value); }),
            ]),
          ]));
      }))));
    await tester.pumpAndSettle();
    final initial = List<int>.of(builds);
    update(() {});
    await tester.pumpAndSettle();
    expect(builds, initial);
    update(() => value = '20');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(builds[0], initial[0]);
    expect(builds[1], initial[1] + 1);
    expect(find.text('10'), findsOneWidget);
    expect(find.text('20'), findsOneWidget);
    await tester.pumpAndSettle();
    update(() { reduced = true; value = '30'; });
    await tester.pumpAndSettle();
    expect(find.text('20'), findsNothing);
    expect(find.text('30'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('浅深主题卡片四角描边不被内容背景覆盖', (tester) async {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      final scheme = ColorScheme.fromSeed(seedColor: Colors.teal, brightness: brightness)
          .copyWith(outlineVariant: const Color(0xffff00ff));
      await tester.pumpWidget(MaterialApp(locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(colorScheme: scheme),
        home: const Scaffold(body: Center(child: RepaintBoundary(key: ValueKey('圆角描边'),
          child: SizedBox(width: 240, child: _MaintenanceCard(title: '基本信息', child: SizedBox(height: 80))),
        )))));
      await tester.pumpAndSettle();
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('圆角描边')));
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 4);
        final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        for (final point in [Offset(15, 15), Offset(image.width - 16, 15),
          Offset(15, image.height - 16), Offset(image.width - 16, image.height - 16)]) {
          final index = (point.dy.toInt() * image.width + point.dx.toInt()) * 4;
          expect(data.getUint8(index) - data.getUint8(index + 1), greaterThan(70));
          expect(data.getUint8(index + 2) - data.getUint8(index + 1), greaterThan(70));
        }
        image.dispose();
      });
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('磁盘复合列表与详情列表分页完整位于卡片内', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    final service = _MaintenanceFixture();
    await tester.pumpWidget(ChangeNotifierProvider<MachineTerminalFileService>.value(value: service,
      child: const MaterialApp(locale: Locale('zh'), localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: _MachineMaintenanceDialog(sessionId: '会话', terminalId: '终端')))));
    await tester.pumpAndSettle();
    final state = tester.state<_MachineMaintenanceDialogState>(find.byType(_MachineMaintenanceDialog));
    state.setState(() {
      state._snapshots[0] = MachineMaintenanceSnapshot({...state._snapshots[0]!.sections,
        'disks': List.generate(24, (i) => 'disk\$i 100 0 2048 30 80 0 4096 40 0 70 80').join('\\n'),
        'network': List.generate(24, (i) => 'eth\$i: 1048576 100 0 0 0 0 0 0 524288 80 0 0 0 0 0 0').join('\\n'),
      });
    });
    await tester.pumpAndSettle();
    final overview = state._overview(state._snapshots[0]!) as ListView;
    final disk = (overview.childrenDelegate as SliverChildListDelegate).children.whereType<_MaintenanceCard>().firstWhere((card) => card.title == '磁盘 IO');
    await tester.pumpWidget(MaterialApp(locale: const Locale('zh'), localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales, home: Scaffold(body: SingleChildScrollView(child: disk))));
    await tester.pumpAndSettle();
    final diskFooter = find.byType(OpenHandTablePagination);
    expect(diskFooter, findsOneWidget);
    expect(tester.getRect(diskFooter).bottom, lessThanOrEqualTo(tester.getRect(find.byType(_MaintenanceCard)).bottom - 10));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(MaterialApp(locale: const Locale('zh'), localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales, home: Scaffold(body: SingleChildScrollView(child: SizedBox(width: 480,
        child: _MaintenanceCard(title: '详情', child: _MaintenanceReadout(section: 'startup', text: List.generate(40, (i) => 'entry\$i enabled').join('\\n'))))))));
    await tester.pumpAndSettle();
    final card = find.byType(_MaintenanceCard);
    final footer = find.byType(OpenHandTablePagination);
    expect(footer, findsOneWidget);
    expect(tester.getRect(footer).bottom, lessThanOrEqualTo(tester.getRect(card).bottom - 10));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox()); await tester.binding.setSurfaceSize(null);
  });

  testWidgets('长列表卡片高度有界且可滚动到底部', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 900));
    await tester.pumpWidget(MaterialApp(locale: const Locale('zh'), localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, home: Scaffold(body: Center(child: SizedBox(width: 600,
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

  testWidgets('采集期间切换只排入最终板块且忽略旧板块错误', (tester) async {
    final service = _MaintenanceFixture();
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    await tester.pumpWidget(ChangeNotifierProvider<MachineTerminalFileService>.value(value: service,
      child: const MaterialApp(locale: Locale('zh'), localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: _MachineMaintenanceDialog(sessionId: '会话', terminalId: '终端')))));
    await tester.pumpAndSettle();
    final state = tester.state<_MachineMaintenanceDialogState>(find.byType(_MachineMaintenanceDialog));
    final pending = Completer<String>();
    service.pending = pending;
    expect(state._loading, isFalse, reason: '初次采集应已结束');
    await tester.tap(find.byTooltip('刷新当前分区'));
    await tester.pump();
    expect(state._loading, isTrue, reason: '第二次采集应在等待结果，错误：\${state._error}');
    final count = service.calls;
    await tester.tap(find.text('进程管理'));
    await tester.pump();
    await tester.tap(find.text('系统服务'));
    await tester.pump();
    expect(state._tab, 2);
    expect(service.calls, count, reason: '切换不得重叠采集');
    service.pending = null;
    pending.completeError(StateError('旧分区失败'));
    await tester.pumpAndSettle();
    expect(service.calls, count + 1, reason: '只刷新最终板块');
    expect(service.lastCommand, contains('section manager'));
    expect(service.lastCommand, isNot(contains('section processes')));
    expect(state._error, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('退场开始即取消采集，迟到结果不再更新面板', (tester) async {
    final service = _MaintenanceFixture();
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    await tester.pumpWidget(ChangeNotifierProvider<MachineTerminalFileService>.value(value: service,
      child: MaterialApp(locale: const Locale('zh'), localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(builder: (context) => Scaffold(body: TextButton(
          onPressed: () => showAnimatedDialog<void>(context: context, builder: (_) =>
            const _MachineMaintenanceDialog(sessionId: '会话', terminalId: '终端')),
          child: const Text('打开运维')))))));
    await tester.tap(find.text('打开运维'));
    await tester.pumpAndSettle();
    final state = tester.state<_MachineMaintenanceDialogState>(find.byType(_MachineMaintenanceDialog));
    final snapshot = state._snapshots[0];
    service.pending = Completer<String>();
    final refresh = state._refresh();
    await tester.pump();
    expect(service.cancelled!(), isFalse);
    Navigator.of(state.context).pop();
    expect(state.mounted, isTrue);
    expect(service.cancelled!(), isTrue);
    service.pending!.complete('');
    await refresh;
    expect(identical(state._snapshots[0], snapshot), isTrue);
    await tester.pumpAndSettle();
    final calls = service.calls;
    await tester.pump(const Duration(seconds: 60));
    expect(service.calls, calls);
    expect(find.byType(_MachineMaintenanceDialog), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('刷新间隔、串行采集、失败暂停与关闭清理', (tester) async {
    final service = _MaintenanceFixture();
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    await tester.pumpWidget(ChangeNotifierProvider<MachineTerminalFileService>.value(value: service,
      child: const MaterialApp(locale: const Locale('zh'), localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, home: Scaffold(body: _MachineMaintenanceDialog(sessionId: '会话', terminalId: '终端')))));
    await tester.pumpAndSettle();
    expect(service.calls, 1);
    expect(service.lastCommand, contains('oh_workers=4'));
    await tester.ensureVisible(find.text('最多 4 个采集进程'));
    await tester.tap(find.text('最多 4 个采集进程'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('最多 2 个采集进程').last);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    await tester.runAsync(() async { await Future<void>.delayed(Duration.zero); });
    await tester.pumpAndSettle();
    expect(_testSettings.maintenanceWorkers, 2);
    await tester.tap(find.byTooltip('开启自动刷新（当前分区）'));
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(service.calls, 2);
    expect(service.probes, 1);
    expect(service.lastCommand, contains('oh_workers=2'));
    await tester.ensureVisible(find.text('10 秒'));
    await tester.tap(find.text('10 秒'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3 秒').last);
    await tester.pumpAndSettle();
    service.pending = Completer<String>();
    final state = tester.state<_MachineMaintenanceDialogState>(find.byType(_MachineMaintenanceDialog));
    final previousBody = state._body;
    await tester.pump(const Duration(seconds: 3));
    expect(identical(previousBody, state._body), isTrue, reason: '刷新开始不应重建已有面板');
    final progress = find.byWidgetPredicate((w) => w is LinearProgressIndicator && w.value == null);
    expect(progress, findsNothing);
    await tester.tap(find.byTooltip('暂停自动刷新'));
    await tester.pump();
    expect(progress, findsNothing);
    expect(tester.widget<_MachineTerminalIconButton>(find.byType(_MachineTerminalIconButton).first).onPressed, isNull);
    expect(tester.widgetList<AnimatedPopupMenuButton<dynamic>>(find.byWidgetPredicate((w) => w is AnimatedPopupMenuButton)).every((w) => !w.enabled), isTrue);
    final count = service.calls;
    await tester.pump(const Duration(seconds: 30));
    expect(service.calls, count);
    service.pending!.completeError(StateError('模拟采集失败'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 30));
    expect(service.calls, count);
    expect(find.textContaining('已暂停自动重试'), findsOneWidget);
    service.pending = Completer<String>();
    await tester.tap(find.byTooltip('刷新当前分区'));
    await tester.pump();
    expect(progress, findsOneWidget);
    expect(service.probes, 2);
    expect(find.byTooltip('暂停自动刷新'), findsNothing);
    expect(progress, findsOneWidget);
    service.pending!.completeError(StateError('模拟手动刷新失败'));
    await tester.pumpAndSettle();
    expect(progress, findsNothing);
    final finalCount = service.calls;
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 60));
    expect(service.calls, finalCount);
    expect(tester.takeException(), isNull);
    await tester.binding.setSurfaceSize(null);
  });
}
''';

const _settingsHarness = '''
late SettingsController _testSettings;
class _MemorySettingsStore extends SettingsStore {
  AppSettingsSnapshot snapshot = AppSettingsSnapshot.defaults();
  bool fail = false;
  @override
  Future<SettingsLoadResult> load() async => SettingsLoadResult(snapshot: snapshot, canPersist: true);
  @override
  Future<void> save(AppSettingsSnapshot value) async {
    if (fail) throw StateError('模拟保存失败');
    snapshot = value;
  }
}
class _SettingsApp extends StatelessWidget {
  const _SettingsApp({this.home, this.locale, this.localizationsDelegates, this.supportedLocales = const [Locale('en', 'US')], this.theme, this.builder});
  final Widget? home;
  final Locale? locale;
  final Iterable<LocalizationsDelegate<dynamic>>? localizationsDelegates;
  final Iterable<Locale> supportedLocales;
  final ThemeData? theme;
  final TransitionBuilder? builder;
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider<SettingsController>.value(value: _testSettings,
    child: MaterialApp(home: home, locale: locale, localizationsDelegates: localizationsDelegates, supportedLocales: supportedLocales, theme: theme, builder: builder));
}
''';

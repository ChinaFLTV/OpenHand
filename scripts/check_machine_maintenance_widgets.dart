import 'dart:io';

import 'support/flutter_widget_check.dart';

Future<void> main() async {
  final root = File.fromUri(Platform.script).parent.parent;
  final panel = await File(
    '${root.path}/lib/features/home/widgets/_home_machine_terminal_panel.dart',
  ).readAsString();
  final containerSource = await File(
    '${root.path}/lib/features/home/widgets/_home_machine_containers.dart',
  ).readAsString();
  final resourceSource = await File(
    '${root.path}/lib/features/home/widgets/_home_machine_container_resources.dart',
  ).readAsString();
  final scheduledSource = await File(
    '${root.path}/lib/features/home/widgets/_home_machine_scheduled_tasks.dart',
  ).readAsString();
  final source = await File(
    '${root.path}/lib/features/home/widgets/_home_machine_maintenance.dart',
  ).readAsString();
  final viewport = panel.substring(
    panel.indexOf('class _MachineTerminalViewport'),
    panel.indexOf('class _MachineTerminalShell'),
  );
  final terminalConstants = panel.substring(
    panel.indexOf('const Color'),
    panel.indexOf('/// 终端画布表面'),
  );
  final terminalTheme = panel.substring(
    panel.indexOf('TerminalTheme _machineTerminalTheme'),
    panel.indexOf('Color _terminalStatusColor'),
  );
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
import 'package:flutter/cupertino.dart' show CupertinoSwitch;
import 'package:xml/xml.dart' as xml;
import 'package:openhand/shared/ui/bounded_animation.dart';
import 'package:openhand/shared/ui/animated_appearance.dart';
import 'package:openhand/shared/ui/openhand_animated_sliver_list.dart';
import 'package:openhand/shared/ui/openhand_animated_chip_wrap.dart';
import 'package:xterm/xterm.dart';
import 'package:openhand/shared/util/platform_shell.dart';
import 'package:flutter/foundation.dart';
import 'package:openhand/app/support/silent_log.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:openhand/app/model/app_settings_snapshot.dart';
import 'package:openhand/app/model/dialog_animation_settings.dart';
import 'package:openhand/app/state/settings_controller.dart';
import 'package:openhand/app/state/settings_store.dart';
import 'package:openhand/shared/db/database_service.dart';
import 'package:openhand/features/machine_terminal/index.dart';
import 'package:openhand/l10n/app_localizations.dart';
import 'package:openhand/app/theme/openhand_theme.dart';
import 'package:openhand/app/theme/openhand_theme_preset.dart';
import 'package:openhand/app/theme/openhand_status_colors.dart';
import 'package:openhand/features/machine_terminal/machine_maintenance.dart';
import 'package:openhand/shared/ui/animated_dialog.dart';
import 'package:openhand/shared/ui/openhand_dialog_action_button.dart';
import 'package:openhand/shared/ui/animated_menu.dart';
import 'package:openhand/shared/util/timer_safety.dart';
import 'package:openhand/shared/ui/motion_preference.dart';
import 'package:openhand/shared/ui/motion_durations.dart';
import 'package:openhand/shared/ui/openhand_spacing.dart';
import 'package:openhand/shared/ui/openhand_clipboard.dart';
import 'package:openhand/shared/ui/openhand_ops_charts.dart';
import 'package:openhand/shared/ui/openhand_ops_press_scale.dart';
import 'package:openhand/shared/ui/openhand_console_log_panel.dart';
import 'package:openhand/shared/ui/openhand_table_pagination.dart';
import 'package:openhand/shared/util/localized_text.dart';
import 'package:openhand/shared/util/localized_units.dart';
import 'package:openhand/shared/util/byte_size_format.dart';
${source.replaceFirst("part of '../openhand_home_page.dart';", '')}
${containerSource.replaceFirst("part of '../openhand_home_page.dart';", '')}
${resourceSource.replaceFirst("part of '../openhand_home_page.dart';", '')}
${scheduledSource.replaceFirst("part of '../openhand_home_page.dart';", '')}
class _MachineTerminalFileManagerDialog extends StatelessWidget {
  const _MachineTerminalFileManagerDialog({required this.sessionId, required this.terminalId, this.targetLabel});
  final String sessionId, terminalId;
  final String? targetLabel;
  @override
  Widget build(BuildContext context) => const SizedBox();
}
$header
$button
$terminalConstants
$terminalTheme
$viewport
${_checks.replaceAll('MaterialApp(', '_SettingsApp(')}
$_settingsHarness
$_scheduledChecks
$_incrementalChecks
$_containerTerminalChecks
$_resourceChecks
$_telemetryChecks
''',
  );
}

const _checks =
    '''
class _MaintenanceFixture extends Fake with ChangeNotifier implements MachineTerminalFileService {
  Completer<String>? taskPending;
  int taskCalls = 0;
  int egressCalls = 0;
  bool egressFail = false;
  Completer<String>? egressPending;
  Future<String> Function(String)? containerRun;
  int calls = 0;
  int probes = 0;
  String lastCommand = "";
  String platform = 'Linux';
  bool powershell = false;
  bool fail = false;
  String? gpuOutput;
  Object? failure;
  Duration? lastTimeout;
  Completer<String>? pending;
  MachineTerminalUploadCancelCheck? cancelled;
  MachineTerminalCommandOutputCallback? outputCallback;
  @override
  Future<String> runMaintenanceCommand({required String sessionId, required String terminalId, required String command, bool windowsScript = false, Duration timeout = const Duration(seconds: 30), int? maxOutputCharacters, MachineTerminalCommandShell commandShell = MachineTerminalCommandShell.posix, MachineTerminalUploadCancelCheck? isCancelled, MachineTerminalCommandOutputCallback? onOutput}) async {
    lastTimeout = timeout;
    if (containerRun != null && RegExp(r"^'(docker|kubectl|podman|nerdctl|crictl|k3s)' ").hasMatch(command)) return containerRun!(command);
    if (command.contains('OH_SHELL_') || command == 'ver') return 'OH_SHELL_bash 5.2';
    if (command == machineTerminalShellProbe) probes++;
    if (commandShell == MachineTerminalCommandShell.probe) return platform == 'Windows' ? (powershell ? 'OH_PS_Windows_NT' : 'OH_CMD_Windows_NT') : platform;
    if (maxOutputCharacters == machineEgressOutputLimit) {
      egressCalls++;
      expectSync(windowsScript, false);
      expectSync(timeout, machineEgressTimeout);
      expectSync(sessionId, isNotEmpty);
      expectSync(terminalId, isNotEmpty);
      if (egressPending != null) return egressPending!.future;
      return egressFail ? '{"success":false}' : '{"ip":"8.8.8.8","country":"United States","city":"Mountain View","connection":{"isp":"Google","asn":15169}}';
    }
    if (onOutput == null && maxOutputCharacters == machineScheduledTaskOutputLimit) {taskCalls++; return taskPending?.future ?? '__OH_TASK__\\tmeta\\tdGVzdGVy\\tVVRD\\tMjAyNi0wOS0zMA==\\n__OH_TASK__\\tavailable\\tY3Jvbg==\\n__OH_TASK__\\tcron\\tdXNlcjp0ZXN0ZXI=\\tdGVzdGVy\\tMCAxICogKiAqIGVjaG8gYmFja3VwCg==\\tMQ==\\n__OH_TASK_END__';}
    expectSync(windowsScript, platform == 'Windows');
    cancelled = isCancelled;
    outputCallback = onOutput;
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
__OH_OPS_listeners__
tcp LISTEN 0 128 0.0.0.0:22 0.0.0.0:* users:(("sshd",pid=42,fd=3))
udp UNCONN 0 0 [::]:5353 [::]:*
__OH_OPS_addresses__
2: eth0: <UP,BROADCAST> mtu 1500 state UP
  inet 10.0.0.2/24 scope global eth0
  inet6 fe80::1/64 scope link
  link/ether 02:00:00:00:00:01
__OH_OPS_proxy__
__OH_PROXY_SCOPE__	系统设置
 HTTPEnable : 1
 HTTPProxy : proxy.example
 HTTPPort : 8080
__OH_OPS_firewall_status__
应用防火墙:
状态: 启用
PF:
状态: 读取权限不足
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
  scheduledTaskChecks();
  containerTerminalChecks();
  resourceChecks();
  telemetryChecks();
  containerInteractionChecks();
  incrementalChecks();
  setUpAll(() async {
    for (final entry in {'运维预览字体': Platform.environment['MAINTENANCE_FONT'], 'MaterialIcons': Platform.environment['MAINTENANCE_ICONS'], 'monospace': Platform.environment['MAINTENANCE_TERMINAL_FONT']}.entries) {
      if (entry.value != null) await (FontLoader(entry.key)..addFont(File(entry.value!).readAsBytes().then((bytes) => ByteData.sublistView(bytes)))).load();
    }
  });
  setUp(() async { _testSettings = await SettingsController.create(store: _MemorySettingsStore()); });
  tearDown(() { _testSettings.dispose(); });
  testWidgets('容器运行时列表、状态菜单和窄屏布局可用', (tester) async {
    final calls = <String>[];
    Future<String> run(String command) async {
      calls.add(command);
      if (command.contains("'context' 'show'")) return 'default';
      if (command.contains("'ps'")) return '{"ID":"abc123","Names":"测试容器","State":"running","Image":"nginx"}';
      return '{}';
    }
    for (final width in [1280.0, 420.0]) {
      await tester.binding.setSurfaceSize(Size(width, 900));
      await tester.pumpWidget(MaterialApp(locale: const Locale('zh'), localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, home: Scaffold(body: _MachineContainerPanel(
        sessionId: '会话', terminalId: '终端', run: run, windows: false,
        shell: MachineTerminalCommandShell.automatic))));
      await selectContainerList(tester);
      await tester.pumpAndSettle();
      expect(find.text('连接上下文 · default'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('容器 · 1'), 220, scrollable:find.descendant(of:find.byType(_MachineContainerPanel),matching:find.byType(Scrollable)).first); await tester.pumpAndSettle();
      expect(find.text('容器 · 1'), findsOneWidget);
      expect(find.byType(OpenHandOperationalRowMenu), findsOneWidget);
      final rowMenu = tester.widget<OpenHandOperationalRowMenu>(find.byType(OpenHandOperationalRowMenu));
      expect(rowMenu.onDetails, isNotNull);
      expect(rowMenu.actions.keys, containsAll(['日志', '终端', '文件管理', '停止', '暂停']));
      expect(rowMenu.actions.keys, isNot(contains('删除')));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
    expect(calls.any((c) => c.contains("'docker' 'stats'")), isTrue);
    await tester.binding.setSurfaceSize(null);
  });
  testWidgets('Docker 不可用时发现 Kubernetes，指标失败保留列表且显式选择不跳转', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1100));
    final calls = <String>[];
    Future<String> run(String command) async {
      calls.add(command);
      if (!command.startsWith("'kubectl'")) throw StateError('command not found');
      if (command.contains("'current-context'")) return '测试集群';
      if (command.contains("'-n' 'forbidden'")) throw StateError('permission denied');
      if (command.contains("'get' 'pods'")) return jsonEncode({'items': [{
        'metadata': {'uid':'pod-1', 'name':'web-pod', 'namespace':'production'},
        'spec': {'nodeName':'node-1', 'containers':[{'name':'web', 'image':'nginx'}]},
        'status': {'phase':'Running', 'containerStatuses':[{'name':'web', 'ready':true, 'state':{'running':{}}}]},
      }]});
      if (command.contains("'version'")) return '{"clientVersion":{"gitVersion":"v1.31"}}';
      if (command.contains("'get' 'nodes'")) return '{"items":[]}';
      throw StateError('Metrics API not available');
    }
    await tester.pumpWidget(MaterialApp(locale:const Locale('zh'),
      localizationsDelegates:AppLocalizations.localizationsDelegates, supportedLocales:AppLocalizations.supportedLocales,
      home:Scaffold(body:_MachineContainerPanel(sessionId:'会话',terminalId:'终端',run:run,
        windows:false,shell:MachineTerminalCommandShell.posix))));
    await selectContainerList(tester);
    await tester.pumpAndSettle();
    final state = tester.state<_MachineContainerPanelState>(find.byType(_MachineContainerPanel));
    expect(state._runtime, MachineContainerRuntime.kubernetes);
    expect(state._entries.length, 2);
    expect(state._entries.where((entry) => entry.running).length, 2);
    expect(state._contextName, '测试集群');
    expect(state._listingFailed, isFalse);
    expect(state._metrics, isEmpty);
    expect(state._collectionIssues['实时资源采样'], contains('Metrics API not available'));
    expect(find.text('自动识别 · Kubernetes'), findsOneWidget);
    state._scope.text = 'forbidden';
    await state.refresh(); await tester.pumpAndSettle();
    expect(state._entries.length, 2);
    expect(state._scope.text, 'forbidden');
    expect(state._appliedScope, '');
    expect(calls.any((command) => command.contains("'-n' 'forbidden'")), isFalse);
    await state.refresh(applyScope:true); await tester.pumpAndSettle();
    expect(state._autoRuntime, isFalse);
    expect(state._entries, isEmpty);
    expect(state._client, isNull);
    expect(state._listingFailed, isTrue);
    expect(calls.any((command) => command.contains("'-n' 'forbidden'")), isTrue);
    expect(calls.any((command) => command.startsWith("'k3s'")), isFalse);
    final before = calls.where((command) => command.startsWith("'kubectl'")).length;
    final menu = tester.widget<_MaintenanceToolbarMenu<String>>(find.byType(_MaintenanceToolbarMenu<String>));
    menu.onSelected('docker');
    await tester.pumpAndSettle();
    expect(state._runtime, MachineContainerRuntime.docker);
    expect(state._autoRuntime, isFalse);
    expect(state._listingFailed, isTrue);
    expect(state._client, isNull);
    expect(find.text('容器 · 0'), findsNothing);
    expect(calls.where((command) => command.startsWith("'kubectl'")).length, before);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('容器刷新失败保留已有数据与操作入口，读取失败可见且恢复后继续使用', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1100));
    var fail = false;
    final calls = <String>[];
    Future<String> run(String command) async {
      calls.add(command);
      if (fail) throw StateError('connection refused');
      if (command.contains("'context' 'show'")) return 'default';
      if (command.contains("'ps'")) return '{"ID":"abc123","Names":"worker","State":"running"}';
      if (command.contains('.State.StartedAt')) return ['"abc123"', '"2026-09-30T08:00:00Z"', '{}'].join(String.fromCharCode(9));
      return '{}';
    }
    await tester.pumpWidget(MaterialApp(locale:const Locale('zh'),
      localizationsDelegates:AppLocalizations.localizationsDelegates, supportedLocales:AppLocalizations.supportedLocales,
      home:Scaffold(body:_MachineContainerPanel(sessionId:'会话',terminalId:'终端',run:run,
        windows:false,shell:MachineTerminalCommandShell.posix))));
    await selectContainerList(tester);
    await tester.pumpAndSettle();
    final state = tester.state<_MachineContainerPanelState>(find.byType(_MachineContainerPanel));
    final entry = state._entries.single;
    fail = true;
    await state.refresh(); await tester.pumpAndSettle();
    expect(state._entries.single, same(entry));
    expect(state._client, isNotNull);
    expect(state._listingFailed, isTrue);
    final menu = tester.widget<OpenHandOperationalRowMenu>(find.byType(OpenHandOperationalRowMenu));
    expect(menu.actions, isNotEmpty); expect(menu.onDetails, isNotNull);
    final attempts = calls.length;
    final opening = state._open(entry, '详情');
    await tester.pumpAndSettle();
    expect(calls.length, greaterThan(attempts));
    final report = tester.state<_ContainerReportDialogState>(find.byType(_ContainerReportDialog));
    expect(report._error, contains('connection refused'));
    await tester.tap(find.byTooltip('关闭')); await tester.pumpAndSettle(); await opening;
    expect(state._busy, isFalse); expect(state._overlay, isFalse);
    fail = false;
    await state.refresh(); await tester.pumpAndSettle();
    expect(state._listingFailed, isFalse);
    expect(state._collectionIssues, isEmpty);
    expect(state._error, isEmpty);
    expect(state._entries.single.name, 'worker');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('容器采集失败保留缓存时仍暂停自动刷新', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1100));
    var fail = false;
    var calls = 0;
    final service = _MaintenanceFixture()..containerRun = (command) async {
      calls++;
      if (fail) throw StateError('connection refused');
      if (command.contains("'context' 'show'")) return 'default';
      if (command.contains("'ps'")) return '{"ID":"abc123","Names":"worker","State":"running"}';
      if (command.contains('.State.StartedAt')) return ['"abc123"', '"2026-09-30T08:00:00Z"', '{}'].join(String.fromCharCode(9));
      return '{}';
    };
    await tester.pumpWidget(ChangeNotifierProvider<MachineTerminalFileService>.value(value:service,
      child:const MaterialApp(locale:Locale('zh'),localizationsDelegates:AppLocalizations.localizationsDelegates,
        supportedLocales:AppLocalizations.supportedLocales,
        home:Scaffold(body:_MachineMaintenanceDialog(sessionId:'会话',terminalId:'终端')))));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('容器管理')); await tester.pumpAndSettle();
    await tester.tap(find.text('容器管理')); await tester.pumpAndSettle();
    final state = tester.state<_MachineMaintenanceDialogState>(find.byType(_MachineMaintenanceDialog));
    final panel = tester.state<_MachineContainerPanelState>(find.byType(_MachineContainerPanel));
    expect(panel._entries.single.name, 'worker');
    state.setState(() => state._automatic = true);
    fail = true;
    await state._refresh(detectShell:false); await tester.pumpAndSettle();
    expect(panel._entries.single.name, 'worker');
    expect(panel._refreshFailed, isTrue);
    expect(panel._telemetryKey.currentState!._issues, isNotEmpty);
    expect(state._automatic, isFalse);
    final stoppedCalls = calls;
    await tester.pump(const Duration(seconds:30));
    expect(calls, stoppedCalls);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('容器面板六种语言、窄屏与大字体保持一致的工具栏和状态布局', (tester) async {
    final locales = [const Locale('zh'), const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      const Locale('en'), const Locale('fr'), const Locale('de'), const Locale('ja')];
    Future<String> run(String command) async {
      if (command.contains("'context' 'show'")) return 'desktop-linux';
      if (command.contains("'ps'")) return [
        jsonEncode({'ID':'abc123','Names':'worker','State':'running','Image':'nginx:stable','CreatedAt':'2026-09-30 08:00:00 +0000 UTC'}),
        jsonEncode({'ID':'abc124','Names':'paused-worker','State':'paused','Image':'redis:stable'}),
      ].join(String.fromCharCode(10));
      if (command.contains("'stats'")) return jsonEncode({'Name':'worker','CPUPerc':'4.2%','MemUsage':'128 MiB / 1 GiB','NetIO':'10 MB / 2 MB'});
      if (command.contains('.State.StartedAt')) return ['abc123','abc124'].map((id) => [jsonEncode(id), '"2026-09-30T08:00:00Z"', '{}'].join(String.fromCharCode(9))).join(String.fromCharCode(10));
      return jsonEncode({'Name':'test-host','ServerVersion':'27.5.1','OperatingSystem':'Linux','Labels':['app=worker'],'ContainersRunning':1});
    }
    for (final locale in locales) {
      final l = await AppLocalizations.delegate.load(locale);
      for (final width in [380.0, 1100.0]) {
        await tester.binding.setSurfaceSize(Size(width, 1100));
        final theme = width < 500 ? OpenHandTheme.dark(OpenHandThemePreset.tundraGreen) : OpenHandTheme.light(OpenHandThemePreset.tundraGreen);
        await tester.pumpWidget(MaterialApp(locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales,
          theme: theme.copyWith(textTheme: theme.textTheme.apply(fontFamily: Platform.environment['MAINTENANCE_FONT'] == null ? null : '运维预览字体')),
          builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(width < 500 ? 1.6 : 1)), child: child!),
          home: Scaffold(body: RepaintBoundary(key: const ValueKey('容器面板预览'), child: _MachineContainerPanel(
            sessionId:'会话', terminalId:'终端', run:run, windows:false, shell:MachineTerminalCommandShell.automatic)))));
        await selectContainerList(tester);
        await tester.pumpAndSettle();
        expect(find.text(l.maintenanceContainerRuntime), findsOneWidget);
        expect(find.text(l.maintenanceContainerContext + ' · desktop-linux'), findsOneWidget);
        expect(find.text(l.maintenanceContainerList + ' · 2'), findsOneWidget);
        expect(find.text('2026-09-30 08:00:00'), findsNWidgets(2));
        expect(find.text('2026-09-30 08:00:00 +0000 UTC'), findsNothing);
        expect(find.text(l.maintenanceContainerReady), findsNothing);
        expect(find.text(l.maintenanceRestartCount), findsNothing);
        final input = find.byWidgetPredicate((widget) => widget is TextField && widget.decoration?.hintText == l.maintenanceContainerSearch);
        expect(tester.getSize(input).height, _maintenanceControlHeight);
        expect(tester.getSize(find.descendant(of: input, matching: find.byType(InputDecorator))).height, _maintenanceControlHeight);
        expect(tester.getSize(find.byType(_MaintenanceToolbarMenu<String>)).height, _maintenanceControlHeight);
        final contextRect = tester.getRect(find.text(l.maintenanceContainerContext + ' · desktop-linux'));
        final searchRect = tester.getRect(input);
        if (width >= 500) {
          expect(contextRect.right, lessThan(searchRect.left));
          expect(searchRect.right, greaterThan(width - 100));
        } else {
          expect(contextRect.bottom, lessThan(searchRect.top));
          expect(searchRect.width, greaterThan(240));
        }
        expect(tester.getSize(find.byTooltip(l.maintenanceRefreshSection)).height, _maintenanceControlHeight);
        expect(tester.getRect(find.byTooltip(l.maintenanceRefreshSection)).right, greaterThan(width - 32));
        for (final decorated in tester.widgetList<DecoratedBox>(find.byType(DecoratedBox))) {
          if (decorated.decoration is BoxDecoration) {
            final decoration = decorated.decoration as BoxDecoration;
            expect(decoration.gradient, isNull);
            expect(decoration.boxShadow ?? [], isEmpty);
          }
        }
        if (Platform.environment['MAINTENANCE_PREVIEW'] != null && locale == const Locale('zh')) {
          await tester.runAsync(() async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('容器面板预览')));
            final image = await boundary.toImage(); final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
            await File('/tmp/container-panel-' + width.toInt().toString() + '.png').writeAsBytes(bytes!.buffer.asUint8List()); image.dispose();
          });
        }
        final state = tester.state<_MachineContainerPanelState>(find.byType(_MachineContainerPanel));
        state.setState(() => state._runtime = MachineContainerRuntime.containerd);
        await tester.pumpAndSettle();
        final scope = find.byTooltip(l.maintenanceContainerScopeDefault);
        expect(scope, findsOneWidget);
        expect(tester.getSize(find.descendant(of:scope, matching:find.byType(TextField))).height, _maintenanceControlHeight);
        final metadata = find.text(l.maintenanceContainerMetadata);
        await tester.scrollUntilVisible(metadata, 220, scrollable: find.descendant(of: find.byType(_MachineContainerPanel), matching: find.byType(Scrollable)).first); await tester.pumpAndSettle();
        await tester.tap(metadata); await tester.pumpAndSettle();
        expect(find.text(l.maintenanceContainerVersion), findsOneWidget);
        expect(find.text('ServerVersion'), findsNothing);
        expect(find.text('27.5.1'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('容器运行时不可用时整个面板显示本地化诊断而非原始异常', (tester) async {
    await tester.binding.setSurfaceSize(const Size(760, 1100));
    for (final locale in [const Locale('zh'), const Locale('en'), const Locale('fr'), const Locale('de'), const Locale('ja'), const Locale.fromSubtags(languageCode:'zh',scriptCode:'Hant')]) {
      final l = await AppLocalizations.delegate.load(locale);
      final theme = OpenHandTheme.light(OpenHandThemePreset.tundraGreen);
      await tester.pumpWidget(MaterialApp(theme:theme.copyWith(textTheme:theme.textTheme.apply(fontFamily:Platform.environment['MAINTENANCE_FONT'] == null ? null : '运维预览字体')),locale:locale, localizationsDelegates:AppLocalizations.localizationsDelegates, supportedLocales:AppLocalizations.supportedLocales,
        home:Scaffold(body:RepaintBoundary(key:const ValueKey('容器异常预览'),child:_MachineContainerPanel(
          sessionId:'会话', terminalId:'终端', windows:false, shell:MachineTerminalCommandShell.automatic,
          run:(_) async => throw StateError('failed to connect to the docker API at unix:///run/docker.sock: no such file or directory'))))));
      await selectContainerList(tester);
      await tester.pumpAndSettle();
      expect(find.text(l.maintenanceContainerUnavailableTitle), findsOneWidget);
      expect(find.text(l.maintenanceContainerNotConnected), findsOneWidget);
      expect(find.text('unix:///run/docker.sock'), findsOneWidget);
      expect(find.textContaining('Bad state:'), findsNothing);
      expect(find.text(l.maintenanceContainerRunning), findsNothing);
      expect(tester.takeException(),isNull);
      if (Platform.environment['MAINTENANCE_PREVIEW'] != null && locale == const Locale('zh')) {
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('容器异常预览')));
          final image = await boundary.toImage(); final bytes = await image.toByteData(format:ui.ImageByteFormat.png);
          await File('/tmp/container-panel-unavailable.png').writeAsBytes(bytes!.buffer.asUint8List()); image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox());
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('容器连接异常和嵌套元数据字段按当前语言显示并保留机器标识', (tester) async {
    for (final locale in [const Locale('zh'), const Locale.fromSubtags(languageCode:'zh',scriptCode:'Hant'), const Locale('en'), const Locale('fr'), const Locale('de'), const Locale('ja')]) {
      final l = await AppLocalizations.delegate.load(locale);
      await tester.binding.setSurfaceSize(const Size(760, 1100));
      await tester.pumpWidget(MaterialApp(locale:locale, localizationsDelegates:AppLocalizations.localizationsDelegates, supportedLocales:AppLocalizations.supportedLocales,
        home:Scaffold(body:SingleChildScrollView(child:Column(children:[
          Builder(builder:(context) {
            expect(maintenanceDetailLabel(context,'metadata / containerStatuses [1] / ready'),
              l.maintenanceContainerMetadataFields + ' / ' + l.maintenanceContainers + ' [1] / ' + l.maintenanceContainerReady);
            expect(maintenanceContainerState(context,'container_running'), l.maintenanceRunning);
            expect(maintenanceContainerState(context,'pending'), l.maintenanceContainerPending);
            expect(maintenanceDetailLabel(context,'compiler'), l.maintenanceContainerCompiler);
            expect(maintenanceDetailLabel(context,'restartCount'), l.maintenanceRestartCount);
            expect(maintenanceDetailLabel(context,'PublishAllPorts'), l.maintenanceContainerPublishAllPorts);
            expect(maintenanceDetailLabel(context,'readinessProbe'), l.maintenanceContainerReadinessProbe);
            expect(maintenanceContainerState(context,'example-custom-state'), 'example-custom-state');
            return const _MaintenanceReadout(section:'container_details', text:'{"metadata":{"name":"worker-原始标识","namespace":"default","labels":{"app.example.io/name":"worker-原始标识"}},"status":{"phase":"Pending"}}');
          }),
          const _MaintenanceReadout(section:'containers', text:'Bad state: failed to connect to the docker API at unix:///run/docker.sock: no such file or directory'),
        ])))));
      await tester.pumpAndSettle();
      expect(find.text(l.maintenanceContainerMetadataFields), findsOneWidget);
      expect(find.text(l.maintenanceContainerPending), findsOneWidget);
      expect(find.text(l.maintenanceContainerUnavailableTitle), findsOneWidget);
      expect(find.text(l.maintenanceContainerNotConnected), findsOneWidget);
      expect(find.text(l.maintenanceContainerConnectionAddress), findsOneWidget);
      expect(find.text('unix:///run/docker.sock'), findsOneWidget);
      expect(find.text('worker-原始标识'), findsNWidgets(2));
      expect(find.textContaining('app.example.io/name'), findsOneWidget);
      expect(find.textContaining('Bad state:'), findsNothing);
      expect(tester.takeException(),isNull);
      await tester.pumpWidget(const SizedBox());
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('容器条目和更多菜单详情共用弹窗，语言切换刷新所有标签', (tester) async {
    Future<String> run(String command) async {
      if(command.contains("'context' 'show'")) return 'default';
      if(command.contains("'ps'")) return '{"ID":"abc123","Names":"worker","State":"running","Image":"nginx"}';
      if(command.contains("'inspect'")) return '{"Name":"worker","ServerVersion":"27.5.1","State":{"Status":"running"}}';
      return '{}';
    }
    Widget screen(Locale locale) => MaterialApp(locale:locale, localizationsDelegates:AppLocalizations.localizationsDelegates, supportedLocales:AppLocalizations.supportedLocales,
      home:Scaffold(body:_MachineContainerPanel(key:const ValueKey('保留容器状态'), sessionId:'会话', terminalId:'终端', run:run, windows:false,shell:MachineTerminalCommandShell.automatic)));
    await tester.binding.setSurfaceSize(const Size(1100,900));
    await tester.pumpWidget(screen(const Locale('zh'))); await selectContainerList(tester); await tester.pumpAndSettle();
    await tester.tap(find.text('worker')); await tester.pumpAndSettle();
    final title = tester.widget<_MachineTerminalDialogHeader>(find.descendant(of:find.byType(_ContainerReportDialog),matching:find.byType(_MachineTerminalDialogHeader))).title;
    expect(title,'worker · 详情'); expect(find.text('服务版本'),findsOneWidget);
    await tester.tap(find.byTooltip('关闭')); await tester.pumpAndSettle();
    await tester.pumpWidget(screen(const Locale('fr'))); await tester.pumpAndSettle();
    final l = await AppLocalizations.delegate.load(const Locale('fr'));
    expect(find.text(l.maintenanceContainerRuntime), findsOneWidget);
    expect(find.text('容器运行时'),findsNothing);
    final menu = tester.widget<OpenHandOperationalRowMenu>(find.byType(OpenHandOperationalRowMenu));
    expect(menu.actions.keys,containsAll([l.maintenanceContainerLogs,l.maintenanceContainerStop,l.maintenanceContainerFileManager]));
    menu.onDetails!(); await tester.pumpAndSettle();
    expect(find.byType(_ContainerReportDialog),findsOneWidget);
    expect(find.text('worker · ' + l.commonDetails),findsOneWidget);
    expect(find.text(l.maintenanceContainerVersion),findsOneWidget);
    expect(find.text('27.5.1'),findsOneWidget);
    expect(tester.takeException(),isNull);
    await tester.tap(find.byTooltip('Fermer')); await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox()); await tester.binding.setSurfaceSize(null);
  });

  testWidgets('容器列对齐桌面布局，CPU 与最近启动时间独立更新且失败不显示旧采样', (tester) async {
    final id = 'a' * 64, stoppedId = 'b' * 64;
    Completer<String>? details, metrics;
    var failMetrics = false, failDetails = false, empty = false;
    Future<String> run(String command) async {
      if (command.contains("'context' 'show'")) return 'default';
      if (command.contains("'ps'")) return empty ? '' : [
        {'ID':id,'Names':'openhand-redis','State':'running','Image':'redis:7-alpine','CreatedAt':'2020-01-01T00:00:00Z','Ports':'0.0.0.0:6379->6379/tcp, [::]:6379->6379/tcp'},
        {'ID':stoppedId,'Names':'openhand-postgresql','State':'exited','Image':'postgres:16-alpine'},
      ].map(jsonEncode).join(String.fromCharCode(10));
      if (command.contains("'stats'")) {
        if (failMetrics) throw StateError('模拟 CPU 采样失败');
        return metrics?.future ?? '{"ID":"aaaaaaaaaaaa","CPUPerc":"234.56%"}';
      }
      if (command.contains('.State.StartedAt')) {
        if (failDetails) throw StateError('模拟补充字段失败');
        return details?.future ?? [
          [jsonEncode(id),'"2026-10-01T08:09:10+08:00"','{}'],
          [jsonEncode(stoppedId),'"0001-01-01T00:00:00Z"',jsonEncode({'5432/tcp':[{'HostIp':'','HostPort':'15432'}]})],
        ].map((fields) => fields.join(String.fromCharCode(9))).join(String.fromCharCode(10));
      }
      return '{}';
    }
    await tester.binding.setSurfaceSize(const Size(1400,1000));
    await tester.pumpWidget(_SettingsApp(locale:const Locale('zh'),localizationsDelegates:AppLocalizations.localizationsDelegates,
      supportedLocales:AppLocalizations.supportedLocales, home:Scaffold(body:_MachineContainerPanel(sessionId:'会话',terminalId:'终端',
        run:run,windows:false,shell:MachineTerminalCommandShell.posix))));
    await selectContainerList(tester);
    await tester.pumpAndSettle();
    final state = tester.state<_MachineContainerPanelState>(find.byType(_MachineContainerPanel));
    _MaintenanceTable table() => tester.widget<_MaintenanceTable>(find.byType(_MaintenanceTable).first);
    expect(table().headers, ['名称','容器标识','镜像','端口','CPU (%)','最近启动时间']);
    expect(table().rows.first.cells, ['openhand-redis','aaaaaaaaaaaa','redis:7-alpine','6379:6379','234.56%','2026-10-01 08:09:10']);
    expect(table().rows.last.cells.sublist(3), ['15432:5432','0%','—']);
    expect(table().rows.first.cellSubtitles![1], id);
    expect(find.text('2020-01-01 00:00:00'), findsNothing);
    expect(tester.takeException(), isNull);
    details = Completer<String>(); metrics = Completer<String>();
    final refreshing = state.refresh(); await tester.pump();
    metrics!.complete('{"ID":"aaaaaaaaaaaa","CPUPerc":"0.44%"}');
    await tester.pump(); await tester.pump(const Duration(milliseconds:700));
    expect(table().rows.first.cells[4], '0.44%'); expect(state._busy, isTrue);
    details!.complete([id,stoppedId].map((id) => [jsonEncode(id),'"2026-10-01T10:11:12Z"','{}'].join(String.fromCharCode(9))).join(String.fromCharCode(10)));
    await refreshing; await tester.pumpAndSettle();
    expect(table().rows.first.cells.last, '2026-10-01 10:11:12');
    failMetrics = true; failDetails = true;
    await state.refresh(); await tester.pumpAndSettle();
    expect(table().rows.first.cells[4], '—'); expect(table().rows.last.cells[4], '0%');
    expect(table().rows.first.cells.last, '—'); expect(state._collectionIssues.length, 2);
    failMetrics = false; failDetails = false; metrics = null; details = null;
    await state.refresh(); await tester.pumpAndSettle();
    expect(table().rows.first.cells[4], '234.56%'); expect(state._collectionIssues, isEmpty);
    empty = true; await state.refresh(); await tester.pumpAndSettle();
    expect(state._listDetails, isEmpty); expect(state._cpuPercentages, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox()); await tester.binding.setSurfaceSize(null);
  });

  testWidgets('容器菜单复制实际运行配置、镜像详情只读展示且六语言窄屏无溢出', (tester) async {
    String? copied;
    var clipboardFails = false;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        if (clipboardFails) throw PlatformException(code:'剪贴板不可用');
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    for (final locale in AppLocalizations.supportedLocales) {
      final l = await AppLocalizations.delegate.load(locale);
      for (final width in [1180.0, 420.0]) {
        var queries = 0;
        var inspectCalls = 0;
        var invalid = false, imageFails = false, historyFails = false;
        Completer<String>? pending;
        final calls = <String>[];
        Future<String> run(String command) async {
          calls.add(command);
          if (command.contains("'context' 'show'")) return 'desktop-linux';
          if (command.contains("'ps'")) { queries++; return '{"ID":"abc123","Names":"worker","State":"running","Image":"app:latest"}'; }
          if (command.contains("'run' '--help'")) return ' --detach --name --entrypoint ';
          if (command.contains("'image' 'inspect'") && imageFails) throw StateError('模拟镜像刷新失败');
          if (command.contains("'image' 'history'") && historyFails) throw StateError('模拟历史读取失败');
          if (command.contains("'image' 'inspect'")) return jsonEncode([{'Id':'sha256:pinned','RepoTags':['app:original'], 'Size':'12345678',
            'Created':'2026-10-01T01:02:03Z','Os':'linux','Architecture':'arm64','Config':{'Env':['MODE=test']},'RootFS':{'Type':'layers','Layers':['sha256:layer']}}]);
          if (command.contains("'image' 'history'")) return jsonEncode({'ID':'layer', 'CreatedBy':'RUN echo "构建记录"', 'Size':'12000000', 'CreatedAt':'2026-10-01T01:02:03Z'});
          if (command.contains('.State.StartedAt')) return ['"abc123"','"2026-09-30T08:00:00Z"','{}'].join(String.fromCharCode(9));
          if (command.contains("'inspect'")) {
            inspectCalls++;
            if (pending != null) return pending!.future;
            return jsonEncode([{'Id':'abc123','Name':'/worker','Image':'sha256:pinned',
              'Config':{'Entrypoint':['/entry'],'Cmd':['serve']},
              'HostConfig':{if (invalid) 'DeviceRequests':[{'Driver':'nvidia'}]}}]);
          }
          return '{}';
        }
        final theme = width == 420 ? OpenHandTheme.dark(OpenHandThemePreset.tundraGreen) : OpenHandTheme.light(OpenHandThemePreset.tundraGreen);
        await tester.binding.setSurfaceSize(Size(width, 960));
        await tester.pumpWidget(MaterialApp(locale:locale, localizationsDelegates:AppLocalizations.localizationsDelegates,
          supportedLocales:AppLocalizations.supportedLocales,
          theme:theme.copyWith(textTheme:theme.textTheme.apply(fontFamily:Platform.environment['MAINTENANCE_FONT'] == null ? null : '运维预览字体')),
          builder:(context, child) => MediaQuery(data:MediaQuery.of(context).copyWith(size:Size(width,960), textScaler:TextScaler.linear(width == 420 ? 1.5 : 1)),child:child!),
          home:Scaffold(body:_MachineContainerPanel(sessionId:'会话',terminalId:'终端',run:run,windows:false,shell:MachineTerminalCommandShell.automatic))));
        await selectContainerList(tester);
        await tester.pumpAndSettle();
        final panel = tester.state<_MachineContainerPanelState>(find.byType(_MachineContainerPanel));
        OpenHandOperationalRowMenu menu() => tester.widget<OpenHandOperationalRowMenu>(find.byType(OpenHandOperationalRowMenu).first);
        final listQueries = queries;
        expect(menu().actions.keys, containsAll([l.maintenanceContainerCopyRun, l.maintenanceContainerImageDetails]));
        copied = null;
        await tester.ensureVisible(find.byType(OpenHandOperationalRowMenu).first); await tester.pumpAndSettle();
        await tester.ensureVisible(find.byType(OpenHandOperationalRowMenu).first); await tester.pumpAndSettle();
        await tester.tap(find.byType(OpenHandOperationalRowMenu).first); await tester.pumpAndSettle();
        expect(find.text(l.maintenanceContainerImageDetails), findsOneWidget);
        await tester.tap(find.text(l.maintenanceContainerCopyRun)); await tester.pumpAndSettle();
        expect(copied, "'docker' '--context' 'desktop-linux' 'run' '--detach' '--name' 'worker' '--entrypoint' '/entry' 'sha256:pinned' 'serve'");
        expect(queries, listQueries); expect(panel._overlay, isFalse);
        final before = copied;
        invalid = true;
        menu().actions[l.maintenanceContainerCopyRun]!(); await tester.pumpAndSettle();
        expect(copied, before); expect(panel._error, l.maintenanceContainerRunIncomplete('DeviceRequests'));
        invalid = false;
        clipboardFails = true;
        menu().actions[l.maintenanceContainerCopyRun]!(); await tester.pumpAndSettle();
        expect(panel._overlay, isFalse); expect(copied, before);
        clipboardFails = false;
        await tester.ensureVisible(find.text('app:latest').first);
        await tester.tap(find.text('app:latest').first); await tester.pumpAndSettle();
        expect(find.byType(_ContainerImageReadout), findsOneWidget);
        expect(find.text(l.maintenanceImageMetadata), findsOneWidget);
        expect(find.text('app:original'), findsOneWidget);
        expect(find.text(l.maintenanceImageBuildCommand), findsOneWidget);
        expect(find.textContaining('2026-10-01'), findsWidgets);
        expect(calls.any((c) => c.contains("'image' 'inspect' 'sha256:pinned'")), isTrue);
        if (width == 1180) {
          final dialog = tester.state<_ContainerReportDialogState>(find.byType(_ContainerReportDialog));
          imageFails = true; await dialog._load(); await tester.pumpAndSettle();
          expect(dialog._error, isNotEmpty); expect(find.text('app:original'), findsOneWidget);
          imageFails = false; historyFails = true; await dialog._load(); await tester.pumpAndSettle();
          expect(find.text(l.maintenanceImageHistoryUnavailable), findsOneWidget);
          expect(find.text('app:original'), findsOneWidget);
          historyFails = false; await dialog._load(); await tester.pumpAndSettle();
          expect(find.text(l.maintenanceImageHistoryUnavailable), findsNothing);
        }
        expect(tester.takeException(), isNull);
        if (Platform.environment['MAINTENANCE_PREVIEW'] != null && locale == const Locale('zh')) {
          await tester.runAsync(() async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(find.ancestor(of:find.byType(_ContainerReportDialog), matching:find.byType(RepaintBoundary)).first);
            final image = await boundary.toImage(pixelRatio:1.5); final bytes = await image.toByteData(format:ui.ImageByteFormat.png);
            await File('/tmp/container-image-' + width.toInt().toString() + '.png').writeAsBytes(bytes!.buffer.asUint8List()); image.dispose();
          });
        }
        await tester.tap(find.descendant(of:find.byType(_ContainerReportDialog), matching:find.byTooltip(openHandCloseLabel(tester.element(find.byType(_ContainerReportDialog)))))); await tester.pumpAndSettle();
        expect(queries, listQueries);
        final initialInspects = inspectCalls;
        pending = Completer<String>();
        final first = panel._open(panel._entries.single, '复制 run 命令'); await tester.pump();
        await panel._open(panel._entries.single, '复制 run 命令');
        expect(inspectCalls, initialInspects + 1);
        await tester.pumpWidget(const SizedBox());
        final stoppedCalls = calls.length;
        pending!.complete('[{"Id":"abc123","Config":{},"HostConfig":{},"Image":"sha256:pinned"}]');
        await first; await tester.pump();
        expect(calls.length, stoppedCalls); expect(copied, before);
        expect(tester.takeException(), isNull);
      }
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('容器日志清屏保留自动刷新并只续收新增日志，六语言窄屏可用', (tester) async {
    final newline = String.fromCharCode(10);
    for (final locale in AppLocalizations.supportedLocales) {
      final l = await AppLocalizations.delegate.load(locale);
      for (final width in [380.0, 1100.0]) {
        await tester.binding.setSurfaceSize(Size(width, 800));
        var output = ['2026-10-01T12:00:00Z 旧日志', '{"message":"原始应用日志"}'].join(newline);
        Completer<String>? pending;
        var calls = 0;
        final theme = OpenHandTheme.light(OpenHandThemePreset.tundraGreen);
        await tester.pumpWidget(MaterialApp(locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: theme.copyWith(textTheme: theme.textTheme.apply(fontFamily: Platform.environment['MAINTENANCE_FONT'] == null ? null : '运维预览字体')),
          builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(width < 500 ? 1.6 : 1)), child: child!),
          home: Scaffold(body: RepaintBoundary(key: const ValueKey('容器日志清屏预览'),
            child: _ContainerReportDialog(title: 'worker · 日志', section: 'logs', load: () async { calls++; return pending?.future ?? output; })))));
        await tester.pumpAndSettle();
        final state = tester.state<_ContainerReportDialogState>(find.byType(_ContainerReportDialog));
        final clear = find.byTooltip(l.maintenanceLogClear);
        expect(clear, findsOneWidget);
        expect(state._text, output);
        final height = tester.getSize(find.byType(OpenHandConsoleFrame)).height;
        await tester.tap(find.byTooltip(l.maintenanceAutoRefresh));
        await tester.pumpAndSettle();
        await tester.tap(clear); await tester.pumpAndSettle();
        expect(state._text, isEmpty); expect(state._logs.entries, isEmpty);
        expect(find.text(l.maintenanceLogEmpty), findsOneWidget);
        expect(state._automatic, isTrue); expect(calls, 1);
        expect(tester.getSize(find.byType(OpenHandConsoleFrame)).height, height);
        await state._load(); await tester.pumpAndSettle();
        expect(state._text, isEmpty);
        output += newline + '2026-10-01T12:00:01Z 新日志';
        await tester.pump(const Duration(seconds: 11)); await tester.pumpAndSettle();
        expect(state._text, '2026-10-01T12:00:01Z 新日志');
        pending = Completer<String>();
        final loading = state._load(); await tester.pump();
        final clearButton = find.descendant(of: clear, matching: find.byType(InkWell));
        expect(tester.widget<InkWell>(clearButton).onTap, isNull);
        pending!.complete(output); await loading; pending = null;
        await tester.pumpAndSettle();
        expect(state._text, '2026-10-01T12:00:01Z 新日志');
        if (Platform.environment['MAINTENANCE_PREVIEW'] != null && locale == const Locale('zh')) {
          await tester.runAsync(() async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('容器日志清屏预览')));
            final image = await boundary.toImage(pixelRatio: 1.5);
            final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
            await File('/tmp/container-log-clear-' + width.toInt().toString() + '.png').writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        final lastCalls = calls;
        await tester.pump(const Duration(seconds: 20)); expect(calls, lastCalls);
      }
    }
    await tester.pumpWidget(MaterialApp(locale: const Locale('zh'), localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales, home: Scaffold(body: _ContainerReportDialog(title: '容器详情', load: () async => '{"Name":"worker"}'))));
    await tester.pumpAndSettle(); expect(find.byTooltip('清屏'), findsNothing);
    await tester.pumpWidget(const SizedBox()); await tester.binding.setSurfaceSize(null);
  });

  testWidgets('容器报告手动刷新、自动刷新失败停止并清理定时器', (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(locale: const Locale('zh'), localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, home: Scaffold(body: _ContainerReportDialog(
      title: '容器日志', section: 'logs', load: () async { calls++; if (calls > 1) throw StateError('日志不可用'); return '第一行\\n第二行'; }))));
    await tester.pumpAndSettle();
    expect(find.textContaining('第一行'), findsOneWidget);
    await tester.tap(find.byTooltip('自动刷新'));
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(calls, 2);
    await tester.pump(const Duration(seconds: 20));
    expect(calls, 2);
    await tester.tap(find.byTooltip('刷新详情'));
    await tester.pumpAndSettle();
    expect(calls, 3);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 20));
    expect(calls, 3);
    expect(tester.takeException(), isNull);
  });
  testWidgets('总览层次紧凑、指标均衡排布、短字段无需内层滚动且六种语言无溢出', (tester) async {
    for (final locale in AppLocalizations.supportedLocales) {
      final l = await AppLocalizations.delegate.load(locale);
      for (final width in [1440.0, 760.0, 390.0]) {
        await tester.binding.setSurfaceSize(Size(width, 1000));
        final service = _MaintenanceFixture();
        final theme = width == 760 ? OpenHandTheme.dark(OpenHandThemePreset.tundraGreen) : OpenHandTheme.light(OpenHandThemePreset.tundraGreen);
        await tester.pumpWidget(ChangeNotifierProvider<MachineTerminalFileService>.value(value: service,
          child: MaterialApp(locale: locale, localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: theme.copyWith(textTheme: theme.textTheme.apply(fontFamily: Platform.environment['MAINTENANCE_FONT'] == null ? null : '运维预览字体')),
            builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(size: Size(width, 1000), textScaler: TextScaler.linear(width == 390 ? 1.6 : 1)), child: child!),
            home: const Scaffold(body: RepaintBoundary(key: ValueKey('运行总览预览'), child: _MachineMaintenanceDialog(sessionId: '会话', terminalId: '终端'))))));
        await tester.pumpAndSettle();
        final state = tester.state<_MachineMaintenanceDialogState>(find.byType(_MachineMaintenanceDialog));
        final newline = String.fromCharCode(10);
        final sections = {...state._snapshots[0]!.sections,
          'host': 'production-worker.example.local', 'processor': 'Apple M4 Pro',
          'core_count': '10', 'uptime': '183600 0', 'load': '1.25 0.94 0.73',
          'system': 'PRETTY_NAME="Ubuntu 26.04 LTS"' + newline + 'Linux worker 6.15.0',
          'memory': ['MemTotal: 33554432 kB','MemAvailable: 10000000 kB','SwapTotal: 0 kB','SwapFree: 0 kB'].join(newline),
          'cpu': ['cpu 400 0 0 600 0 0 0 0','cpu0 200 0 0 300 0 0 0 0','cpu1 200 0 0 300 0 0 0 0'].join(newline),
        };
        state.setState(() {
          state._snapshots[0] = MachineMaintenanceSnapshot(sections);
          state._previous[0] = MachineMaintenanceSnapshot({...sections, 'cpu': ['cpu 100 0 0 300 0 0 0 0','cpu0 50 0 0 150 0 0 0 0','cpu1 50 0 0 150 0 0 0 0'].join(newline)});
          state._cpuHistory..clear()..addAll(List.generate(12, (i) => (time: i * 10000.0, value: .2 + (i % 4) * .1)));
          state._bodyIdentity = null;
        });
        await tester.pumpAndSettle();
        if (Platform.environment['MAINTENANCE_PREVIEW'] != null) {
          await tester.runAsync(() async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('运行总览预览')));
            final image = await boundary.toImage(pixelRatio: 1.5); final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
            await File('/tmp/maintenance-overview-' + locale.toString() + '-' + width.toInt().toString() + '.png').writeAsBytes(bytes!.buffer.asUint8List()); image.dispose();
          });
        }
        final summary = tester.widget<_MaintenanceGrid>(find.byKey(const ValueKey('maintenance-overview-summary')));
        final summaryRects = [for (final child in summary.children) tester.getRect(find.byWidget(child))];
        for (final rect in summaryRects) {
          expect(rect.width, closeTo(summaryRects.first.width, .01));
          expect(rect.height, closeTo(summaryRects.first.height, .01), reason: '摘要等高：' + locale.toString() + '，宽度 ' + width.toString() + '，位置 ' + summaryRects.toString());
        }
        final panels = tester.widget<_MaintenanceGrid>(find.byKey(const ValueKey('maintenance-overview-resources'))).children.cast<_MaintenanceCard>();
        expect(panels.any((card) => card.title == l.maintenanceResourceUse), isFalse);
        final basic = panels.firstWhere((card) => card.title == l.maintenanceBasicInfo);
        final basicFinder = find.byWidget(basic);
        expect(find.descendant(of: basicFinder, matching: find.byType(_MaintenanceFields)), findsNothing);
        expect(find.descendant(of: basicFinder, matching: find.text('production-worker.example.local')), findsOneWidget);
        expect(find.descendant(of: basicFinder, matching: find.text('Apple M4 Pro')), findsOneWidget);
        expect(find.text('cpu0 · 50%'), findsNothing);
        expect(find.text('50.0%'), findsOneWidget);
        expect(find.textContaining(l.maintenanceCoreLabel('0') + ' · '), findsOneWidget);
        expect(find.text('负载均衡'), findsNothing);
        expect(find.byTooltip(l.maintenanceLoadIntervals), findsOneWidget);
        if (width == 1440) {
          final firstRow = [for (final card in panels.take(3)) tester.getRect(find.byWidget(card))];
          for (final rect in firstRow) {
            expect(rect.width, closeTo(firstRow.first.width, .01));
            expect(rect.height, closeTo(firstRow.first.height, .01), reason: '首排等高：' + locale.toString() + '，位置 ' + firstRow.toString());
            expect(rect.top, closeTo(firstRow.first.top, .01));
          }
          expect(firstRow.first.height, lessThan(340), reason: '首排高度：' + locale.toString());
          final fields = tester.getRect(find.byType(_MaintenanceFacts).first);
          expect(fields.bottom, lessThanOrEqualTo(firstRow.first.bottom));
          final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
          await mouse.addPointer(location: Offset.zero); await mouse.moveTo(firstRow.first.center); await tester.pumpAndSettle();
          for (final box in tester.widgetList<DecoratedBox>(find.descendant(of: basicFinder, matching: find.byType(DecoratedBox)))) {
            if (box.decoration case final BoxDecoration decoration) {
              expect(decoration.gradient, isNull); expect(decoration.boxShadow ?? [], isEmpty);
            }
          }
          await mouse.removePointer();
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('总览内存分布填满网格，其余分布卡保持紧凑宽度', (tester) async {
    final service = _MaintenanceFixture();
    for (final width in [1400.0, 360.0]) {
      await tester.binding.setSurfaceSize(Size(width, 1100));
      await tester.pumpWidget(ChangeNotifierProvider<MachineTerminalFileService>.value(value: service,
        child: const MaterialApp(locale: Locale('zh'), localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: _MachineMaintenanceDialog(sessionId: '会话', terminalId: '终端')))));
      await tester.pumpAndSettle();
      final state = tester.state<_MachineMaintenanceDialogState>(find.byType(_MachineMaintenanceDialog));
      final data = MachineMaintenanceSnapshot({...state._snapshots[0]!.sections,
        'sockets': 'tcp LISTEN 0 128 0.0.0.0:22 0.0.0.0:*',
        'gpu_nvidia': 'GPU-1,NVIDIA Test,550.1,00000000:01:00.0,45,1024,8192,60,80.5,150,1800,7000,0,P2',
      });
      for (final tab in [0, 2, 3, 4]) {
        state.setState(() { state._snapshots[tab] = data; state._tab = tab; state._bodyIdentity = null; });
        await tester.pumpAndSettle();
        final cards = find.byWidgetPredicate((w) => w is _MaintenanceCard && w.child is _MaintenanceVisual && (w.child as _MaintenanceVisual).donut);
        if (cards.evaluate().isEmpty) {
          final page = find.descendant(of: find.byType(_MachineMaintenanceDialog), matching: find.byType(CustomScrollView)).first;
          await tester.scrollUntilVisible(cards, 300, scrollable: find.descendant(of: page, matching: find.byType(Scrollable)).first);
          await tester.pumpAndSettle();
        }
        expect(cards, findsOneWidget, reason: '分区 ' + tab.toString());
        final painted = find.descendant(of: cards, matching: find.byWidgetPredicate((w) => w is Container && w.foregroundDecoration != null)).first;
        if (tab == 0) {
          expect(tester.getSize(painted).width, closeTo(tester.getSize(cards).width, .01));
        } else {
          expect(tester.getSize(painted).width, lessThanOrEqualTo(380));
        }
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    }
    await tester.binding.setSurfaceSize(null);
  });
  testWidgets('分布图例聚合名称、数值和占比，窄屏大字体自动纵排', (tester) async {
    for (final brightness in Brightness.values) {
      for (final scale in [1.0, 1.8]) {
        for (final width in [1280.0, 380.0, 300.0]) {
          await tester.binding.setSurfaceSize(Size(width, 800));
          await tester.pumpWidget(MaterialApp(locale: const Locale('zh'), localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: brightness == Brightness.light ? OpenHandTheme.light(OpenHandThemePreset.tundraGreen) : OpenHandTheme.dark(OpenHandThemePreset.tundraGreen),
            home: MediaQuery(data: MediaQueryData(size: Size(width, 800), textScaler: TextScaler.linear(scale)),
              child: const Scaffold(body: Align(alignment: Alignment.topLeft, child: _MaintenanceCard(
                title: '服务状态分布',
                child: _MaintenanceVisual(donut: true, segments: [
                  OpenHandChartSegment(label: '未运行', value: 287, color: Colors.purple),
                  OpenHandChartSegment(label: '运行中', value: 268, color: Colors.green),
                ])))))));
          await tester.pumpAndSettle();
          final chart = find.byWidgetPredicate((w) => w is CustomPaint && w.painter is OpenHandDonutChartPainter);
          final chartRect = tester.getRect(chart);
          final labelRect = tester.getRect(find.text('未运行'));
          final valueRect = tester.getRect(find.text('287'));
          final shareRect = tester.getRect(find.text('51.7%'));
          final frame = find.descendant(of: find.byType(_MaintenanceCard), matching: find.byWidgetPredicate((w) => w is Container && w.foregroundDecoration != null)).first;
          if (scale == 1) expect(tester.getSize(frame).width, lessThan(360));
          expect(chartRect.size, Size.square(_maintenanceDonutSize * scale.clamp(1.0, 1.4)));
          expect(valueRect.left, closeTo(labelRect.left, .5));
          expect(valueRect.top - labelRect.bottom, inInclusiveRange(0, 5));
          expect(shareRect.left - valueRect.right, inInclusiveRange(0, 10));
          if (scale > 1 || width < 380) {
            expect(labelRect.top, greaterThan(chartRect.bottom));
          } else {
            expect(labelRect.left, greaterThan(chartRect.right));
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        }
      }
    }
    await tester.binding.setSurfaceSize(null);
  });
  testWidgets('网格紧凑卡不保留空列，同排内容卡接收剩余宽度', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 600));
    await tester.pumpWidget(MaterialApp(locale: const Locale('zh'), localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: _MaintenanceGrid(maxColumns: 2, children: [
        _MaintenanceCard(title: '分布卡', child: _MaintenanceVisual(donut: true, segments: [
          OpenHandChartSegment(label: '运行中', value: 268, color: Colors.green),
          OpenHandChartSegment(label: '未运行', value: 287, color: Colors.purple),
        ])),
        _MaintenanceCard(title: '趋势卡', child: SizedBox(height: 120)),
        _MaintenanceCard(title: '紧凑卡甲', child: _MaintenanceVisual(donut: true, segments: [
          OpenHandChartSegment(label: '已用', value: 18, color: Colors.green),
        ])),
        _MaintenanceCard(title: '紧凑卡乙', child: _MaintenanceVisual(donut: true, segments: [
          OpenHandChartSegment(label: '可用', value: 14, color: Colors.blue),
        ])),
      ]))));
    await tester.pumpAndSettle();
    final rects = [for (final card in find.byType(_MaintenanceCard).evaluate()) tester.getRect(find.byWidget(card.widget))];
    expect(rects[0].width, lessThan(360));
    expect(rects[1].left - rects[0].right, 12);
    expect(rects[1].right, 1400);
    expect(rects[2].width, lessThan(360));
    expect(rects[3].width, lessThan(360));
    expect(rects[3].left - rects[2].right, 12);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });
  testWidgets('行操作按钮在明暗主题、紧凑行和列宽调整后保持小方形、行间距及表头对齐', (tester) async {
    for (final brightness in Brightness.values) {
      for (final compact in [false, true]) {
        for (final width in [1280.0, 420.0]) {
          await tester.binding.setSurfaceSize(Size(width, 600));
          await tester.pumpWidget(MaterialApp(
            theme: brightness == Brightness.light ? OpenHandTheme.light(OpenHandThemePreset.tundraGreen) : OpenHandTheme.dark(OpenHandThemePreset.tundraGreen),
            locale: const Locale('zh'), localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: Align(alignment: Alignment.topLeft, child: OpenHandOperationalRankTable(
              headers: const ['PID', '进程', '状态', '累计 CPU 时间'], compact: compact,
              rows: const [
                OpenHandOperationalRankRow(value: 3, cells: ['285', '测试进程甲', '休眠', '100 毫秒']),
                OpenHandOperationalRankRow(value: 2, cells: ['286', '测试进程乙', '休眠', '200 毫秒']),
                OpenHandOperationalRankRow(value: 1, cells: ['287', '测试进程丙', '休眠', '300 毫秒']),
              ],
              onRowTap: (_) {},
            ))),
          ));
          await tester.pumpAndSettle();
          final button = find.descendant(of: find.byType(OpenHandOperationalRowMenu), matching: find.byType(IconButton));
          expect(button, findsNWidgets(3));
          void checkButtons() {
            for (var i = 0; i < 3; i++) {
              final rect = tester.getRect(button.at(i));
              expect(tester.getSize(button.at(i)), const Size.square(28));
              expect(rect.center.dx, closeTo(tester.getCenter(find.text('操作')).dx, .5));
              if (i > 0) expect(rect.top - tester.getRect(button.at(i - 1)).bottom, greaterThanOrEqualTo(16));
            }
          }
          checkButtons();
          final handle = find.byWidgetPredicate((w) => w is MouseRegion && w.cursor == SystemMouseCursors.resizeColumn).last;
          await tester.drag(handle, const Offset(-1000, 0), warnIfMissed: false);
          await tester.pumpAndSettle();
          checkButtons();
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        }
      }
    }
    await tester.binding.setSurfaceSize(null);
  });
  testWidgets('共用图标菜单在狭窄和拉伸布局下不变成长胶囊，禁用时不打开', (tester) async {
    for (final width in [28.0, 120.0]) {
      await tester.pumpWidget(MaterialApp(theme: OpenHandTheme.light(OpenHandThemePreset.tundraGreen),
        home: Scaffold(body: Center(child: SizedBox(width: width, height: 80,
          child: AnimatedPopupMenuButton<String>(enabled: false,
            itemBuilder: (_) => [const PopupMenuItem(value: '详情', child: Text('详情'))]))))));
      await tester.pumpAndSettle();
      final button = tester.renderObject<RenderBox>(find.byType(IconButton));
      final origin = button.localToGlobal(Offset.zero);
      final end = button.localToGlobal(Offset(button.size.width, button.size.height));
      expect(end.dx - origin.dx, closeTo(end.dy - origin.dy, .5));
      expect(end.dx - origin.dx, lessThanOrEqualTo(width));
      await tester.tap(find.byType(AnimatedPopupMenuButton<String>));
      await tester.pumpAndSettle();
      expect(find.text('详情'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
  });
  testWidgets('行点击和更多菜单详情共用入口，业务操作不触发行点击', (tester) async {
    const row = OpenHandOperationalRankRow(cells: ['测试条目'], value: 1);
    var details = 0, stopped = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: OpenHandOperationalRankTable(
      headers: const ['名称'], rows: const [row],
      onRowTap: (value) { expect(identical(value, row), isTrue); details++; },
      rowActions: (_) => {'停止': () => stopped++},
    ))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('测试条目').first);
    expect(details, 1);
    await tester.tap(find.byType(OpenHandOperationalRowMenu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Details').last);
    await tester.pumpAndSettle();
    expect(details, 2); expect(stopped, 0);
    await tester.tap(find.byType(OpenHandOperationalRowMenu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('停止').last);
    await tester.pumpAndSettle();
    expect(details, 2); expect(stopped, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('菜单业务动作复用详情确认流程，取消不执行命令', (tester) async {
    var executed = 0;
    await tester.pumpWidget(MaterialApp(locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: _MachineMaintenanceDetails(
        title: '测试服务', load: () async => '__OH_OPS_platform__\\nDarwin\\n__OH_OPS_status__\\n状态: running\\n__OH_OPS_end__\\n',
        actions: const {'停止': '测试命令'}, initialAction: '停止',
        execute: (_) async { executed++; return ''; },
      ))));
    await tester.pumpAndSettle();
    expect(find.text('确认执行'), findsOneWidget);
    expect(executed, 0);
    await tester.tap(find.text('取消').last);
    await tester.pumpAndSettle();
    expect(executed, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
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

  testWidgets('提示卡在拉伸父布局中按内容收拢，长文本遵守宽度上限', (tester) async {
    for (final width in [320.0, 1280.0]) {
      await tester.binding.setSurfaceSize(Size(width, 800));
      for (final error in [false, true]) {
        for (final scale in [1.0, 1.8]) {
          for (final message in ['连接失败', List.filled(80, '请检查终端连接后重试。').join()]) {
            await tester.pumpWidget(MaterialApp(home: MediaQuery(
              data: MediaQueryData(size: Size(width, 800), textScaler: TextScaler.linear(scale)),
              child: Scaffold(body: Padding(padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [_MaintenanceNotice(message: message, error: error)]))))));
            await tester.pumpAndSettle();
            final notice = find.byType(_MaintenanceNotice);
            final card = tester.getRect(find.descendant(of: notice, matching: find.byType(Container)).first);
            expect(card.width, lessThanOrEqualTo(math.min(_maintenanceNoticeMaxWidth, width - 32)));
            expect(card.center.dx, closeTo(width / 2, .01));
            if (message == '连接失败') {
              final text = tester.getSize(find.text(message));
              expect(card.width - text.width, lessThan(80));
            } else {
              final state = tester.state<_MaintenanceNoticeState>(notice);
              expect(state._scrollController.position.maxScrollExtent, greaterThan(0));
            }
            expect(tester.takeException(), isNull);
          }
        }
      }
    }
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
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

  testWidgets('协议统计六种语言完整翻译、切换语言保留展开、长标签布局稳定', (tester) async {
    const output = 'tcp:\\n\\t12 packets sent\\n\\t\\t4 data packets (2048 bytes) retransmitted\\n'
      'icmp6:\\n\\t79 calls to icmp_error\\n\\tOutput histogram:\\n\\t\\tunreach: 79\\n'
      '\\tInput histogram:\\n\\t\\tunreach: 807\\n';
    for (final width in [360.0, 1200.0]) {
      await tester.binding.setSurfaceSize(Size(width, 1000));
      for (final locale in AppLocalizations.supportedLocales) {
        await tester.pumpWidget(MaterialApp(locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(brightness: width == 360 ? Brightness.dark : Brightness.light,
            fontFamily: Platform.environment['MAINTENANCE_FONT'] == null ? null : '运维预览字体'),
          builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(width == 360 ? 1.5 : 1)), child: child!),
          home: Scaffold(body: RepaintBoundary(key: const ValueKey('协议统计预览'), child: SingleChildScrollView(child:
            _MaintenanceCard(title: '网络协议与错误统计', scrollBody: false, child: _MaintenanceReadout(text: output, section: 'network_stats')))))));
        await tester.pumpAndSettle();
        final context = tester.element(find.byType(_MaintenanceReadout).first);
        final l = AppLocalizations.of(context)!;
        expect(find.text(l.maintenanceNetCounterPacketsSent), findsOneWidget);
        expect(find.text(l.maintenanceNetCounterRetransmittedData('2048')), findsOneWidget);
        expect(find.text('unreach'), findsNothing);
        expect(find.text('79'), findsNWidgets(2));
        expect(find.text('807'), findsOneWidget);
        expect(find.byType(_MaintenanceFields), findsNothing);
        expect(find.byType(OpenHandOperationalRankTable), findsNWidgets(4));
        for (final field in ['packet sent', 'URG only packet', 'resend initiated by MTU discovery',
          'challenge ACK sent due to unexpected SYN', 'error not generated because rate limitation',
          'calls to icmp_error', 'no route', 'address unreachable', 'beyond scope', 'unrecognized next header',
          'ActiveOpens', 'PassiveOpens', 'InSegs', 'OutSegs', 'RetransSegs', 'InCsumErrors', 'InHdrErrors']) {
          expect(maintenanceNetworkCounterLabel(context, field), isNotNull, reason: field);
        }
        expect(maintenanceNetworkCounterLabel(context, 'packet sent'), maintenanceNetworkCounterLabel(context, 'packets sent'));
        expect(maintenanceNetworkCounterLabel(context, 'future_metric'), isNull);
        expect(maintenanceNetworkCounterLabel(context, 'data packet ({v0} byte)'), isNull);
        expect(maintenanceGpuFieldValue(context, 'Result', 'success'), l.maintenanceReadoutSuccess);
        expect(maintenanceGpuFieldValue(context, 'LoadState', 'not-found'), l.maintenanceReadoutNotFound);
        expect(maintenanceGpuFieldValue(context, 'SubState', 'dead'), l.maintenanceStopped);
        expect(maintenanceGpuFieldValue(context, 'ActiveState', 'inactive'), l.maintenanceStopped);
        expect(maintenanceGpuFieldValue(context, 'MemoryCurrent', '18446744073709551615'), l.maintenanceUnavailable);
        expect(maintenanceGpuFieldValue(context, 'product_name', 'Success'), 'Success');
        expect(maintenanceGpuFieldValue(context, 'path', '/tmp/active'), '/tmp/active');
        expect(maintenanceGpuFieldLabel(context, 'ecc_errors/volatile/single_bit/total'),
          l.maintenanceGpuDetailEcc + ' › ' + l.maintenanceReadoutVolatile + ' › ' + l.maintenanceReadoutSingleBit + ' › ' + l.maintenanceReadoutTotal);
        expect(tester.takeException(), isNull);
        if (locale.toString() == 'zh' && width == 1200 && Platform.environment['MAINTENANCE_FONT'] != null) {
          await tester.runAsync(() async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('协议统计预览')));
            final image = await boundary.toImage(pixelRatio: 1.5);
            final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
            await File('/tmp/openhand-network-i18n-preview.png').writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      }
      await tester.pumpWidget(const SizedBox());
    }
    await tester.binding.setSurfaceSize(null);
  });
  testWidgets('统计未知字段保留来源且语言切换保留折叠状态', (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 900));
    Future<void> show(Locale locale) async {
      await tester.pumpWidget(MaterialApp(locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: _MaintenanceReadout(section: 'network_stats', text: 'tcp:\\n  7 future_metric'))));
      await tester.pumpAndSettle();
    }
    await show(const Locale('zh'));
    expect(find.text('扩展指标 1'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.byTooltip('原始字段：future_metric'), findsOneWidget);
    expect(find.text('future_metric'), findsNothing);
    final context = tester.element(find.byType(_MaintenanceReadout).first);
    final l = AppLocalizations.of(context)!;
    expect(_maintenanceReadoutValue(context, 'MemoryCurrent', '18446744073709551615'), l.maintenanceUnavailable);
    expect(_maintenanceReadoutValue(context, 'Restart', 'on-failure'), l.maintenanceReadoutRestartFailure);
    expect(_maintenanceReadoutValue(context, 'NotifyAccess', 'main'), l.maintenanceReadoutNotifyMain);
    expect(maintenanceDetailValue(context, 'main', field: '进程'), 'main');
    expect(maintenanceDetailValue(context, 'on-failure', field: '名称'), 'on-failure');
    await tester.tap(find.text('TCP 协议统计')); await tester.pumpAndSettle();
    expect(find.text('7'), findsNothing);
    await show(const Locale('de'));
    expect(find.text('7'), findsNothing);
    final german = AppLocalizations.of(tester.element(find.byType(_MaintenanceReadout).first))!;
    await tester.tap(find.text(german.maintenanceReadoutProtocolStats('TCP'))); await tester.pumpAndSettle();
    expect(find.text('7'), findsOneWidget);
    expect(find.text(german.maintenanceReadoutUnknownMetric('1')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });
  testWidgets('出口信息按当前语言分组，窄屏、大字体与明暗主题布局稳定', (tester) async {
    final report = MachineEgressReport.parse(jsonEncode({
      'ip': '2001:4860:4860::8888', 'country': 'United States', 'country_code': 'US',
      'continent': 'North America', 'continent_code': 'NA', 'region': 'California',
      'city': 'Mountain View', 'latitude': 37.386, 'longitude': -122.0838,
      'connection': {'asn': 15169, 'org': 'Google LLC', 'isp': 'Google', 'domain': 'google.com'},
      'timezone': {'id': 'America/Los_Angeles', 'is_dst': true},
      'is_eu': false, 'capital': 'Washington D.C.',
      'extra': {'network_role': 'resolver'},
    }), source: 'https://ipwho.is/');
    for (final locale in AppLocalizations.supportedLocales) {
      for (final width in [360.0, 1280.0]) {
        await tester.binding.setSurfaceSize(Size(width, 1100));
        final theme = width == 360 ? OpenHandTheme.dark(OpenHandThemePreset.tundraGreen) : OpenHandTheme.light(OpenHandThemePreset.tundraGreen);
        await tester.pumpWidget(MaterialApp(locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales,
          theme: Platform.environment['MAINTENANCE_FONT'] == null ? theme : theme.copyWith(textTheme: theme.textTheme.apply(fontFamily: '运维预览字体')),
          builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(width == 360 ? 1.5 : 1)), child: child!),
          home: Scaffold(body: SingleChildScrollView(child: RepaintBoundary(key: const ValueKey('出口预览'), child: _MaintenanceEgressCard(report: report, busy: false, error: null, onRefresh: () {}))))));
        await tester.pumpAndSettle();
        final context = tester.element(find.byType(_MaintenanceEgressCard));
        final l = AppLocalizations.of(context)!;
        expect(find.text(l.maintenanceEgressTitle), findsOneWidget);
        expect(find.text(l.maintenanceEgressCity), findsOneWidget);
        expect(find.text(l.maintenanceEgressIsp), findsOneWidget);
        expect(find.text('Google'), findsOneWidget);
        expect(find.text(report.ip), findsOneWidget);
        expect(find.byType(OpenHandOperationalRankTable), findsNothing);
        final country = switch (locale.languageCode) {
          'zh' => locale.scriptCode == 'Hant' ? '美國' : '美国',
          'de' => 'Vereinigte Staaten', 'fr' => 'États-Unis', 'ja' => 'アメリカ合衆国', _ => 'United States',
        };
        expect(find.text(country), findsOneWidget);
        expect(find.text('Mountain View'), findsOneWidget);
        expect(find.textContaining(l.maintenanceEgressSource + ' · ' + report.source), findsOneWidget);
        final copy = find.byTooltip(l.commonCopy + ' IP');
        final refresh = find.byTooltip(l.maintenanceEgressRefresh);
        expect(tester.getSize(copy), tester.getSize(refresh));
        expect(tester.getRect(refresh).left - tester.getRect(copy).right, greaterThanOrEqualTo(8));
        expect(maintenanceEgressValue(context, report, '夏令时', 'true'), l.maintenanceHealthParsedYes);
        expect(maintenanceEgressValue(context, report, '机房', 'Original data'), 'Original data');
        expect(find.textContaining('{"ip"'), findsNothing);
        expect(tester.takeException(), isNull);
        if (locale.toString() == 'zh' && width == 1280 && Platform.environment['MAINTENANCE_FONT'] != null) {
          final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('出口预览')));
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 1.5);
            final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
            await File('/tmp/openhand-egress-preview.png').writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox());
      }
    }
    await tester.binding.setSurfaceSize(null);
  });
  testWidgets('出口扩展信息展开后刷新保留状态，未知字段可核对原始标识', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1100));
    final report = MachineEgressReport.parse(jsonEncode({
      'ip': '8.8.8.8', 'extra': {'network_role': 'resolver'},
    }), source: 'https://ipwho.is/');
    Future<void> show({bool busy = false, String? error}) async {
      await tester.pumpWidget(MaterialApp(locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: SingleChildScrollView(child: _MaintenanceEgressCard(
          report: report, busy: busy, error: error, onRefresh: () {})))));
      await tester.pump(const Duration(seconds: 1));
    }
    await show();
    final context = tester.element(find.byType(_MaintenanceEgressCard));
    final l = AppLocalizations.of(context)!;
    expect(maintenanceEgressValue(context, report, '国家或地区', 'United States'), '美国');
    expect(maintenanceEgressValue(context, report, '洲', 'Asia'), '亚洲');
    expect(maintenanceEgressValue(context, report, '国家或地区', 'Unrecognized'), 'Unrecognized');
    await tester.tap(find.text('补充信息')); await tester.pumpAndSettle();
    expect(find.text('resolver'), findsOneWidget);
    expect(find.text(l.maintenanceEgressExtraField + ' 1'), findsOneWidget);
    expect(find.byTooltip('extra.network_role'), findsOneWidget);
    await show(busy: true);
    expect(find.text('resolver'), findsOneWidget);
    final refresh = tester.widget<_MachineTerminalIconButton>(find.byWidgetPredicate(
      (widget) => widget is _MachineTerminalIconButton && widget.tooltip == l.maintenanceEgressRefresh));
    expect(refresh.onPressed, isNull);
    await show(error: 'request'); await tester.pumpAndSettle();
    expect(find.text(l.maintenanceEgressStale), findsOneWidget);
    expect(find.text('8.8.8.8'), findsOneWidget);
    expect(find.text('resolver'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });
  testWidgets('出口查询复用目标终端，缓存、独立刷新、失败保留结果及取消有效', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1000));
    for (final platform in ['Linux', 'Darwin', 'Windows']) {
      final service = _MaintenanceFixture()..platform = platform;
      await tester.pumpWidget(ChangeNotifierProvider<MachineTerminalFileService>.value(value: service,
        child: const MaterialApp(locale: Locale('zh'), localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales, home: Scaffold(body: _MachineMaintenanceDialog(sessionId: '会话', terminalId: '终端')))));
      await tester.pumpAndSettle();
      final state = tester.state<_MachineMaintenanceDialogState>(find.byType(_MachineMaintenanceDialog));
      state.setState(() => state._tab = 3);
      await state._refresh(detectShell: false); await tester.pumpAndSettle();
      expect(service.egressCalls, 1); expect(state._egress!.ip, '8.8.8.8');
      await state._refresh(detectShell: false); await tester.pumpAndSettle();
      expect(service.egressCalls, 1);
      final cached = state._egress!;
      state._egress = MachineEgressReport(ip: cached.ip, version: cached.version, source: cached.source,
        collectedAt: DateTime.now().subtract(const Duration(minutes: 6)), groups: cached.groups);
      await state._refresh(detectShell: false); await tester.pumpAndSettle();
      expect(service.egressCalls, 2);
      final old = state._egress;
      final calls = service.calls;
      service.egressFail = true;
      await state._refresh(manual: true, egressOnly: true); await tester.pumpAndSettle();
      expect(service.calls, calls); expect(service.egressCalls, 4);
      expect(identical(state._egress, old), isTrue); expect(state._error, isNull);
      expect(state._egressError, isNotNull);
      await state._refresh(detectShell: false); await tester.pumpAndSettle();
      expect(service.egressCalls, 4);
      service.egressFail = false;
      final pending = Completer<String>(); service.egressPending = pending;
      final refresh = state._refresh(manual: true, egressOnly: true);
      await tester.pump();
      expect(state._egressBusy, isTrue);
      final duplicate = state._refresh(manual: true, egressOnly: true);
      await duplicate; expect(service.egressCalls, 5);
      await tester.pumpWidget(const SizedBox());
      pending.complete('{"ip":"1.1.1.1"}'); await refresh; await tester.pump();
      expect(service.egressCalls, 5); expect(tester.takeException(), isNull);
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

  testWidgets('动态 DNS、账户与传感器记录统一使用列表', (tester) async {
    for (final width in [420.0, 1200.0]) {
      await tester.binding.setSurfaceSize(Size(width, 900));
      final service = _MaintenanceFixture();
      await tester.pumpWidget(ChangeNotifierProvider<MachineTerminalFileService>.value(
        value: service, child: const MaterialApp(locale: Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: _MachineMaintenanceDialog(sessionId: '会话', terminalId: '终端')))));
      await tester.pumpAndSettle();
      final state = tester.state<_MachineMaintenanceDialogState>(find.byType(_MachineMaintenanceDialog));
      state.setState(() {
        state._tab = 3;
        state._snapshots[3] = MachineMaintenanceSnapshot({
          'platform': 'Linux',
          'dns': 'nameserver 114.114.114.114\\nnameserver 218.104.111.122\\nnameserver 202.103.24.68',
        });
      });
      await tester.pumpAndSettle();
      final dnsCard = find.byWidgetPredicate((widget) =>
        widget is _MaintenanceCard && widget.title == 'DNS 服务器');
      await tester.scrollUntilVisible(dnsCard, 300,
        scrollable: find.descendant(of: find.byType(CustomScrollView).first,
          matching: find.byType(Scrollable)).first);
      await tester.pumpAndSettle();
      final table = tester.widget<_MaintenanceTable>(find.descendant(
        of: dnsCard, matching: find.byType(_MaintenanceTable)));
      expect(table.rows.map((row) => row.cells.last).toList(),
        ['114.114.114.114', '218.104.111.122', '202.103.24.68']);
      expect(find.descendant(of: dnsCard, matching: find.byType(_MaintenanceFacts)), findsNothing);
      expect(tester.takeException(), isNull);
      final diagnostics = find.byWidgetPredicate((widget) =>
        widget is _MaintenanceCard && widget.title == '诊断项目');
      await tester.scrollUntilVisible(diagnostics, 300,
        scrollable: find.descendant(of: find.byType(CustomScrollView).first,
          matching: find.byType(Scrollable)).first);
      await tester.pumpAndSettle();
      expect(find.descendant(of: diagnostics, matching: find.byType(_MaintenanceTable)), findsOneWidget);
      expect(find.descendant(of: diagnostics, matching: find.byType(_MaintenanceGrid)), findsNothing);
      await tester.pumpWidget(const SizedBox());

      final accounts = MachineHealthReport.parse('accounts',
        '@user\\tuid\\thome\\tshell\\nreader\\t1000\\t/home/reader\\t/bin/bash', '0');
      await tester.pumpWidget(MaterialApp(locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: SingleChildScrollView(child:
          _MaintenanceHealthContent(report: accounts, raw: '')))));
      await tester.pumpAndSettle();
      expect(find.byType(_MaintenanceTable), findsOneWidget);
      expect(find.byType(_MaintenanceFields), findsNothing);
      expect(find.text('reader'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());

      await tester.pumpWidget(MaterialApp(locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: SingleChildScrollView(child: _MaintenanceMetricContent(
          data: MachineMaintenanceSnapshot({'platform': 'Linux',
            'sensors': 'temp1: 42000\\ntemp2: 39000\\ntemp3: 40000'}),
          section: 'sensors')))));
      await tester.pumpAndSettle();
      expect(find.byType(_MaintenanceTable), findsOneWidget);
      expect(find.byType(_MaintenanceMetricTiles), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('健康字段与诊断结构化展示且宽窄屏无溢出', (tester) async {
    await tester.runAsync(() async {
      for (final entry in {'运维预览字体': Platform.environment['MAINTENANCE_FONT'], 'MaterialIcons': Platform.environment['MAINTENANCE_ICONS'], 'monospace': Platform.environment['MAINTENANCE_TERMINAL_FONT']}.entries) {
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
    void checkHealthStatusEdges() {
      for (final card in tester.widgetList<_MaintenanceCard>(find.byType(_MaintenanceCard))) {
        if (card.trailing is! _MaintenanceStatus) continue;
        final cardFinder = find.byWidget(card);
        final status = find.descendant(of:cardFinder,matching:find.byType(_MaintenanceStatus));
        final capsule = find.descendant(of:status,matching:find.byType(Container));
        expect(tester.getRect(capsule).right,closeTo(tester.getRect(cardFinder).right - 11,0.01));
      }
    }
    checkHealthStatusEdges();
    expect(find.text('系统名称'), findsOneWidget);
    expect(find.textContaining('<plist>'), findsNothing);
    expect(find.text('You need administrator access to run this tool... exiting!'), findsNothing);
    expect(tester.takeException(), isNull);
    if (Platform.environment['MAINTENANCE_FONT'] != null) {
      await tester.scrollUntilVisible(find.text('日期、时间与时区'), 250, scrollable:find.descendant(of:find.byType(CustomScrollView),matching:find.byType(Scrollable)).first);
      await tester.pumpAndSettle();
      checkHealthStatusEdges();
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
    checkHealthStatusEdges();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('控制台连续文本支持跨行选择且窄屏折叠滚动稳定', (tester) async {
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
    final logText = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(logText.textSpan!.toPlainText(), '[info] 服务已启动\\n[warning] 连接重试\\n[error] 请求超时');
    expect(find.byType(ListView), findsNothing);
    expect(find.byType(CustomScrollView), findsNothing);
    logText.onSelectionChanged!(const TextSelection(baseOffset: 7, extentOffset: 25), SelectionChangedCause.drag);
    await tester.pumpAndSettle();
    final logState = tester.state<_MaintenanceLogBrowserState>(find.byType(_MaintenanceLogBrowser));
    expect(logState._follow, isFalse);
    expect(logState._selecting, isTrue);
    buffer.append('追加日志');
    logState.setState(() {});
    await tester.pumpAndSettle();
    expect(tester.widget<SelectableText>(find.byType(SelectableText)).textSpan!.toPlainText(), logText.textSpan!.toPlainText());
    if (Platform.environment['MAINTENANCE_FONT'] != null) {
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('日志预览')));
      await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1.5);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('/tmp/maintenance-log-console-preview.png').writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
      });
    }
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
    expect(find.text('/etc/logrotate.conf'), findsOneWidget);
    expect(find.byType(_MaintenanceFields), findsOneWidget);
    await tester.tap(find.text('日志目录大小 · 1')); await tester.pumpAndSettle();
    expect(find.text(formatByteSize(4096 * 1024)), findsOneWidget);
    expect(find.text('/var/log'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox()); await tester.binding.setSurfaceSize(null);
  });

  testWidgets('日志工具栏统一高度圆角且统计靠右，窄屏换行不溢出', (tester) async {
    for (final width in [360.0, 760.0, 1280.0]) {
      for (final brightness in [Brightness.light, Brightness.dark]) {
        await tester.binding.setSurfaceSize(Size(width, 900));
        await tester.pumpWidget(MaterialApp(locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.green, brightness: brightness)),
          home: Scaffold(body: _MaintenanceLogBrowser(buffers: {'system': MachineLogBuffer()},
            data: MachineMaintenanceSnapshot({'platform': 'Linux'})))));
        await tester.pumpAndSettle();
        final follow = find.byKey(const ValueKey('maintenance-log-follow'));
        final lastCount = find.byKey(const ValueKey('maintenance-log-count-2'));
        final panel = find.byType(OpenHandConsoleFrame).first;
        expect(tester.getSize(follow).height, _maintenanceControlHeight);
        expect(tester.getRect(lastCount).right, closeTo(tester.getRect(panel).right, 1));
        final chip = tester.widget<FilterChip>(follow);
        expect((chip.shape! as RoundedRectangleBorder).borderRadius, BorderRadius.circular(8));
        for (var i = 0; i < 3; i++) {
          final counter = find.byKey(ValueKey('maintenance-log-count-\$i'));
          expect(tester.getSize(counter).height, _maintenanceControlHeight);
          expect(tester.getRect(counter).left, greaterThanOrEqualTo(12));
        }
        if (width == 1280) {
          expect(tester.getRect(follow).top, tester.getRect(lastCount).top);
        } else {
          expect(tester.getRect(lastCount).top, greaterThanOrEqualTo(tester.getRect(follow).bottom));
        }
        final state = tester.state<_MaintenanceLogBrowserState>(find.byType(_MaintenanceLogBrowser));
        final wasFollowing = state._follow;
        await tester.tap(follow); await tester.pumpAndSettle();
        expect(state._follow, !wasFollowing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('日志管理清屏隔离来源并重置选区计数，刷新期间禁用且保留筛选', (tester) async {
    final newline = String.fromCharCode(10);
    final system = MachineLogBuffer()..append(['error 旧日志', 'warning 旧日志'].join(newline));
    final kernel = MachineLogBuffer()..append('内核记录');
    final theme = OpenHandTheme.light(OpenHandThemePreset.tundraGreen);
    Widget host({bool busy = false}) => MaterialApp(locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales,
      theme: theme.copyWith(textTheme: theme.textTheme.apply(fontFamily: Platform.environment['MAINTENANCE_FONT'] == null ? null : '运维预览字体')),
      home: Scaffold(body: RepaintBoundary(key: const ValueKey('日志管理清屏预览'),
        child: _MaintenanceLogBrowser(buffers: {'system': system, 'kernel': kernel}, busy: busy,
          data: MachineMaintenanceSnapshot({'platform': 'Linux', 'log_config': '/etc/logrotate.conf' + newline + 'weekly'})))));
    await tester.binding.setSurfaceSize(const Size(1100, 800));
    await tester.pumpWidget(host()); await tester.pumpAndSettle();
    final clear = find.byTooltip('清屏');
    expect(tester.getSize(clear).height, _maintenanceControlHeight);
    final state = tester.state<_MaintenanceLogBrowserState>(find.byType(_MaintenanceLogBrowser));
    await tester.enterText(find.byType(TextField), '日志'); await tester.pumpAndSettle();
    state.setState(() { state._selecting = true; state._follow = false; });
    await tester.pumpAndSettle();
    await tester.pumpWidget(host(busy: true)); await tester.pumpAndSettle();
    expect(tester.widget<InkWell>(find.descendant(of: clear, matching: find.byType(InkWell))).onTap, isNull);
    expect(system.entries.length, 2);
    await tester.pumpWidget(host()); await tester.pumpAndSettle();
    await tester.tap(clear); await tester.pumpAndSettle();
    expect(system.entries, isEmpty); expect(kernel.entries.single.message, '内核记录');
    expect(state._visible, isEmpty); expect(state._selecting, isFalse);
    expect(state._query, '日志'); expect(state._follow, isFalse);
    expect(find.text('错误 0'), findsOneWidget); expect(find.text('警告 0'), findsOneWidget);
    expect(find.text('暂无日志记录'), findsOneWidget);
    system.append(['error 旧日志', 'warning 旧日志'].join(newline));
    await tester.pumpWidget(host()); await tester.pumpAndSettle();
    expect(state._visible, isEmpty);
    system.append(['warning 旧日志', 'info 新日志'].join(newline));
    await tester.pumpWidget(host()); await tester.pumpAndSettle();
    expect(state._visible.single.message, 'info 新日志'); expect(find.text('信息 1'), findsOneWidget);
    if (Platform.environment['MAINTENANCE_PREVIEW'] != null) {
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('日志管理清屏预览')));
        final image = await boundary.toImage(pixelRatio: 1.5);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('/tmp/maintenance-log-clear.png').writeAsBytes(bytes!.buffer.asUint8List()); image.dispose();
      });
    }
    await tester.enterText(find.byType(TextField), ''); await tester.pumpAndSettle();
    tester.widget<_MaintenanceToolbarMenu<String>>(find.byType(_MaintenanceToolbarMenu<String>)).onSelected('kernel');
    await tester.pumpAndSettle();
    expect(state._visible.single.message, '内核记录');
    await tester.tap(clear); await tester.pumpAndSettle();
    expect(kernel.entries, isEmpty); expect(system.entries.single.message, 'info 新日志');
    expect(find.text('轮转记录与配置'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox()); await tester.binding.setSurfaceSize(null);
  });

  testWidgets('日志空态、错误和筛选空态均填满折叠区剩余高度', (tester) async {
    for (final size in [const Size(760, 700), const Size(420, 900)]) {
      await tester.binding.setSurfaceSize(size);
      for (final mode in ['empty', 'error', 'filtered', 'content']) {
        final buffer = MachineLogBuffer();
        if (mode == 'error') buffer.append('dmesg: Operation not permitted');
        if (mode == 'filtered' || mode == 'content') buffer.append('完整日志');
        await tester.pumpWidget(MaterialApp(locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: _MaintenanceLogBrowser(buffers: {'system': buffer},
            data: MachineMaintenanceSnapshot({'platform': 'Linux', 'log_config': '/etc/logrotate.conf\\nweekly'})))));
        await tester.pumpAndSettle();
        if (mode == 'filtered') {
          await tester.enterText(find.byType(TextField), '不存在');
          await tester.pumpAndSettle();
        }
        final panel = find.byType(OpenHandConsoleFrame).first;
        final fold = find.byType(ExpansionTile);
        final collapsedHeight = tester.getSize(panel).height;
        for (final expanded in [true, false]) {
          expect(tester.getRect(fold).bottom, closeTo(size.height - _maintenancePanelBottomInset, 1));
          expect(tester.getRect(fold).top - tester.getRect(panel).bottom, closeTo(8, 1));
          await tester.tap(find.text('轮转记录与配置'));
          await tester.pump(const Duration(milliseconds: 50));
          expect(tester.takeException(), isNull);
          await tester.pumpAndSettle();
          expect(tester.getSize(panel).height, expanded ? lessThan(collapsedHeight) : closeTo(collapsedHeight, 1));
          expect(tester.getRect(fold).bottom, closeTo(size.height - _maintenancePanelBottomInset, 1));
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    }
    await tester.binding.setSurfaceSize(null);
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
    state.setState(() => state._metadataKind = 'config');
    await tester.pumpAndSettle();
    expect(find.text('/etc/logrotate.conf'), findsOneWidget);
    expect(find.byType(_MaintenanceFields), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox()); await tester.binding.setSurfaceSize(null);
  });

  testWidgets('时钟源列表与固定指标分开展示，局部失败不隐藏有效数据', (tester) async {
    for (final width in [360.0, 1200.0]) {
      await tester.binding.setSurfaceSize(Size(width, 900));
      final report = MachineHealthReport.parse('ntp',
        'Last offset : -0.00012 seconds\\n^* 2001:db8::1 2 6 377 20 +12us[+14us] +/- 1ms\\n@@OH_TIME:Chrony 选择详情\\n@@OH_RESULT:1', '0');
      await tester.pumpWidget(MaterialApp(locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: SingleChildScrollView(child: _MaintenanceHealthContent(report: report, raw: '诊断原文')))));
      await tester.pumpAndSettle();
      expect(find.text('-0.00012 seconds'), findsOneWidget);
      expect(find.text('Chrony 时钟源'), findsOneWidget);
      expect(find.byType(_MaintenanceTable), findsOneWidget);
      expect(find.byType(_MaintenanceFields), findsWidgets);
      expect(find.text('部分指标不可用，已保留成功采集的数据'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('NTP 部分可用时展示紧凑状态，说明折叠且适配六种语言和窄屏', (tester) async {
    const raw = 'configured: /etc/ntp.conf\\nNetwork Time Server: time.apple.com\\n实时同步状态: 原生 timed 不提供当前选中源及偏移查询接口\\n测量说明: 最多测量 3 个配置源；只读 SNTP 结果不代表系统当前选中源，不修改时钟';
    final report = MachineHealthReport.parse('ntp', raw, '0');
    expect(report.issue, 'partial');
    for (final locale in AppLocalizations.supportedLocales) {
      for (final width in [360.0, 1200.0]) {
        await tester.binding.setSurfaceSize(Size(width, 1100));
        final theme = OpenHandTheme.light(OpenHandThemePreset.tundraGreen);
        final l = lookupAppLocalizations(locale);
        await tester.pumpWidget(MaterialApp(locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales,
          theme: Platform.environment['MAINTENANCE_FONT'] == null ? theme : theme.copyWith(textTheme: theme.textTheme.apply(fontFamily: '运维预览字体')),
          home: Scaffold(body: SingleChildScrollView(child: RepaintBoundary(key: const ValueKey('NTP布局预览'),
            child: _MaintenanceCard(title: l.maintenanceHealthNtp, scrollBody: false,
              icon: Icons.access_time_filled, accent: OpenHandStatusColors.warning,
              trailing: const _MaintenanceStatus(label: '待检查', color: OpenHandStatusColors.warning),
              child: _MaintenanceHealthContent(report: report, raw: raw)))))));
        await tester.pumpAndSettle();
        expect(find.byType(_MaintenanceEmptyHint), findsNothing);
        expect(find.text('/etc/ntp.conf'), findsOneWidget);
        expect(find.text('time.apple.com'), findsOneWidget);
        expect(tester.widget<_MaintenanceFields>(find.byType(_MaintenanceFields)).rows.length, 2);
        expect(find.text(l.maintenanceHealthNativeTimedLimit), findsNothing);
        final statusRect = tester.getRect(find.text(l.maintenanceHealthPartial));
        final fieldsRect = tester.getRect(find.byType(_MaintenanceFields));
        expect(fieldsRect.top - statusRect.bottom, lessThan(32));
        if (Platform.environment['MAINTENANCE_PREVIEW'] != null && locale.toString() == 'zh') {
          await tester.runAsync(() async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('NTP布局预览')));
            final image = await boundary.toImage();
            final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
            await File('/tmp/maintenance-ntp-\${width.toInt()}.png').writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.tap(find.byType(ExpansionTile)); await tester.pumpAndSettle();
        expect(find.text(l.maintenanceHealthSyncStatus), findsOneWidget);
        expect(find.text(l.maintenanceHealthNativeTimedLimit), findsOneWidget);
        expect(find.text(l.maintenanceHealthSntpNotes), findsOneWidget);
        expect(find.text('部分输出格式尚未识别，请检查采集工具版本和数据范围'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('共用分页器按实际宽度换行，适配页数、语言和字体', (tester) async {
    for (final locale in ['zh', 'en', 'de']) {
      for (final scale in [1.0, 1.5]) {
        for (final total in [26, 26000]) {
          await tester.binding.setSurfaceSize(const Size(1600, 400));
          await tester.pumpWidget(MaterialApp(locale: Locale(locale),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: MediaQuery(data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Align(alignment: Alignment.topLeft, child: OpenHandTablePagination(
                total: total, page: 1, pageSize: 20, bar: true,
                onPageChanged: (_) {}, onPageSizeChanged: (_) {}))))));
          await tester.pumpAndSettle();
          final groups = find.descendant(of: find.byType(OpenHandTablePagination),
            matching: find.byType(SingleChildScrollView));
          expect(groups, findsNWidgets(2));
          final requiredWidth = tester.getSize(groups.at(0)).width +
            tester.getSize(groups.at(1)).width + kOpenHandTablePagerClusterGap + 24;
          for (final extra in [1.0, -1.0, 1.0]) {
            await tester.binding.setSurfaceSize(Size(requiredWidth + extra, 400));
            await tester.pumpAndSettle();
            final first = tester.getRect(groups.at(0));
            final second = tester.getRect(groups.at(1));
            if (extra > 0) {
              expect(first.center.dy, closeTo(second.center.dy, .1));
            } else {
              expect(second.top, greaterThanOrEqualTo(first.bottom));
            }
            expect(tester.takeException(), isNull);
          }
          await tester.binding.setSurfaceSize(const Size(240, 400));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        }
      }
    }
    await tester.binding.setSurfaceSize(null);
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
        for (final entry in {'运维预览字体': Platform.environment['MAINTENANCE_FONT'], 'MaterialIcons': Platform.environment['MAINTENANCE_ICONS'], 'monospace': Platform.environment['MAINTENANCE_TERMINAL_FONT']}.entries) {
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
        });
        await tester.pumpWidget(MaterialApp(locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(fontFamily: '运维预览字体', colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff526914), brightness: brightness)),
          home: Scaffold(body: RepaintBoundary(key: const ValueKey('固定指标预览'), child: ListView(padding: const EdgeInsets.all(24), children: [
            for (final section in ['memory', 'pressure'])
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
              for (final section in ['pressure', 'memory'])
                _MaintenanceCard(title: section, scrollBody: false,
                  child: _MaintenanceMetricContent(data: data, section: section)),
            ])))))));
        await tester.pumpAndSettle();
        expect(find.byType(OpenHandOperationalRankTable), findsNothing);
        expect(find.text('30.2 GB'), findsOneWidget);
        expect(find.text('扩展指标：metric44'), findsOneWidget);
        expect(find.text('12.5%'), findsOneWidget);
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

  testWidgets('同行等高支持内容增长缩短、换行、大字号和反向布局', (tester) async {
    for (final width in [1000.0, 560.0, 320.0]) {
      await tester.binding.setSurfaceSize(Size(width, 1000));
      for (final scale in [1.0, 1.8]) {
        for (final direction in TextDirection.values) {
          for (final height in [120.0, 180.0, 60.0]) {
            await tester.pumpWidget(MaterialApp(home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Directionality(textDirection: direction, child: Scaffold(
                body: SingleChildScrollView(child: _MaintenanceGrid(minWidth: 200, children: [
                  for (var i = 0; i < 5; i++)
                    Container(key: ValueKey(i), color: Colors.teal,
                      child: LayoutBuilder(builder: (_, constraints) => SingleChildScrollView(
                        child: SizedBox(height: i.isEven ? height : 30, child: Text('卡片'))))),
                ])))))));
            await tester.pumpAndSettle();
            final rows = <double, Rect>{};
            for (var i = 0; i < 5; i++) {
              final rect = tester.getRect(find.byKey(ValueKey(i)));
              final first = rows.putIfAbsent(rect.top, () => rect);
              expect(rect.height, closeTo(first.height, .01));
              expect(rect.left, greaterThanOrEqualTo(0));
              expect(rect.right, lessThanOrEqualTo(width + .01));
              expect(rect.height, lessThanOrEqualTo(height));
            }
            final ordered = rows.values.toList()..sort((a, b) => a.top.compareTo(b.top));
            for (var i = 1; i < ordered.length; i++) {
              expect(ordered[i].top - ordered[i - 1].bottom, closeTo(_maintenanceGridGap, .01));
            }
            expect(tester.takeException(), isNull);
          }
        }
      }
    }
    await tester.pumpWidget(const SizedBox());
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
    expect(find.text('1 小时'), findsOneWidget);
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
    await tester.tap(find.text('1 小时'));
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

  testWidgets('卡片尾部状态胶囊的可见边缘靠右，窄屏大字体和六种语言保持稳定', (tester) async {
    for (final locale in [const Locale('zh'), const Locale.fromSubtags(languageCode:'zh',scriptCode:'Hant'), const Locale('en'), const Locale('fr'), const Locale('de'), const Locale('ja')]) {
      for (final width in [320.0, 720.0, 1800.0]) {
        for (final scale in [1.0, 1.8]) {
          for (final canOpen in [false, true]) {
            await tester.binding.setSurfaceSize(Size(width, 900));
            await tester.pumpWidget(MaterialApp(locale:locale, localizationsDelegates:AppLocalizations.localizationsDelegates, supportedLocales:AppLocalizations.supportedLocales,
              home:MediaQuery(data:MediaQueryData(size:Size(width,900),textScaler:TextScaler.linear(scale)),
                child:Scaffold(body:Column(children:[
                  for (final label in ['健康','异常','待检查'])
                    _MaintenanceCard(title:'日期、时间与时区', icon:Icons.schedule, scrollBody:false, onOpen:canOpen ? () {} : null,
                      trailing:_MaintenanceStatus(label:label,color:Colors.green), child:const SizedBox(height:20)),
                ])))));
            await tester.pumpAndSettle();
            for (final card in find.byType(_MaintenanceCard).evaluate()) {
              final cardFinder = find.byWidget(card.widget);
              final status = find.descendant(of:cardFinder,matching:find.byType(_MaintenanceStatus));
              final capsule = find.descendant(of:status,matching:find.byType(Container));
              final cardRect = tester.getRect(cardFinder);
              final capsuleRect = tester.getRect(capsule);
              final edge = canOpen
                ? tester.getRect(find.descendant(of:cardFinder,matching:find.byIcon(Icons.chevron_right_rounded))).left - 3
                : cardRect.right - 11;
              expect(capsuleRect.right,closeTo(edge,0.01));
              expect(capsuleRect.width,greaterThan(20));
              expect(tester.getRect(status).width,closeTo(capsuleRect.width,0.01));
            }
            expect(tester.takeException(),isNull);
            await tester.pumpWidget(const SizedBox());
          }
        }
      }
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('共用状态胶囊服从外层左右对齐，不占满表格列宽', (tester) async {
    for (final alignment in [Alignment.centerLeft,Alignment.centerRight]) {
      await tester.pumpWidget(MaterialApp(locale:const Locale('zh'),localizationsDelegates:AppLocalizations.localizationsDelegates,supportedLocales:AppLocalizations.supportedLocales,
        home:Scaffold(body:Align(alignment:Alignment.topLeft,child:SizedBox(key:const ValueKey('状态单元格'),width:240,height:48,
          child:Align(alignment:alignment,child:const _MaintenanceStatus(label:'健康',color:Colors.green)))))));
      await tester.pumpAndSettle();
      final cellRect=tester.getRect(find.byKey(const ValueKey('状态单元格')));
      final status=find.byType(_MaintenanceStatus);
      final capsuleRect=tester.getRect(find.descendant(of:status,matching:find.byType(Container)));
      if (alignment==Alignment.centerLeft) {
        expect(capsuleRect.left,closeTo(cellRect.left,0.01));
      } else {
        expect(capsuleRect.right,closeTo(cellRect.right,0.01));
      }
      expect(tester.getRect(status).width,lessThan(cellRect.width));
      expect(tester.takeException(),isNull);
    }
    await tester.pumpWidget(const SizedBox());
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
      expect(maintenanceDetailValue(context, 'Darwin'), l10n.maintenanceMacos);
      expect(maintenanceDetailValue(context, 'builtin'), l10n.maintenanceBusBuiltin);
      expect(maintenanceDetailValue(context, 'metal4'), 'Metal 4');
      expect(machineMaintenanceTimestamp('Tue Sep 29 19:22 2026'), '2026-09-29 19:22:00');
      expect(maintenanceDetailValue(context, '2026-08-18T18:01:59.123Z', field: 'State / StartedAt'), '2026-08-18 18:01:59');
      expect(maintenanceDetailValue(context, '2026-08-18T18:01:59Z', field: 'conditions / lastTransitionTime'), '2026-08-18 18:01:59');
      expect(maintenanceDetailValue(context, '2026-08-18T18:01:59Z', field: 'CommandLine'), '2026-08-18T18:01:59Z');
      expect(maintenanceDetailValue(context, '1787047319999999999', field: 'PID'), '1787047319999999999');
      expect(maintenanceHealthValue(context, '20260818180159.000000+480', field: 'LastBootUpTime'), '2026-08-18 18:01:59');
      expect(maintenanceHealthValue(context, '2026-08-18T18:01:59Z', field: 'user'), '2026-08-18T18:01:59Z');
      expect(maintenanceHealthValue(context, 'Darwin'), l10n.maintenanceMacos);
      expect(maintenanceHealthValue(context, 'Sep 29 18:41:39 2026'), '2026-09-29 18:41:39');
      expect(maintenanceHealthValue(context, '- 10:26 (00:00)'), l10n.maintenanceExited);

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



  testWidgets('元数据字段统一尺寸，详情按钮保持圆形且长值可完整查看复制', (tester) async {
    final longValue = List.filled(30, '/srv/runtime/containers/worker').join(' · ');
    final fields = <List<String>>[
      ['服务名称', 'worker'], ['状态', '运行中'], ['挂载路径', longValue],
      ['累计 CPU 时间', '24270.37 s'], ['版本', '27.0.1'], ['配置说明', '第一行\\n第二行\\n第三行\\n第四行'],
    ];
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    for (final brightness in Brightness.values) {
      for (final width in [360.0, 760.0, 1280.0]) {
        for (final scale in [1.0, 1.6]) {
          await tester.binding.setSurfaceSize(Size(width, 1000));
          await tester.pumpWidget(MaterialApp(locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales,
            theme: (brightness == Brightness.light
              ? OpenHandTheme.light(OpenHandThemePreset.tundraGreen)
              : OpenHandTheme.dark(OpenHandThemePreset.tundraGreen)).copyWith(
                visualDensity: const VisualDensity(horizontal: -2, vertical: -4)),
            builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
            home: Scaffold(body: SingleChildScrollView(child: _MaintenanceFields(rows: fields)))));
          await tester.pumpAndSettle();
          final rects = [for (var i = 0; i < fields.length; i++) tester.getRect(find.byWidgetPredicate((w) => w is AnimatedContainer && w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('maintenance-field-')).at(i))];
          for (final rect in rects) {
            expect(rect.width, closeTo(rects.first.width, .01));
            expect(rect.height, closeTo(rects.first.height, .01));
            expect(rect.right, lessThanOrEqualTo(width + .01));
          }
          final buttons = find.descendant(of: find.byType(_MaintenanceFields), matching: find.byType(IconButton));
          expect(buttons, findsAtLeastNWidgets(2));
          for (var index = 0; index < buttons.evaluate().length; index++) {
            final button = buttons.at(index);
            final material = find.descendant(of: button, matching: find.byType(Material));
            final rect = tester.getRect(material);
            expect(rect.size, const Size.square(28));
            expect(tester.getSize(button), const Size.square(28));
            expect(tester.widget<Material>(material).shape, isA<CircleBorder>());
            expect(tester.getCenter(find.descendant(of: button, matching: find.byType(Icon))), rect.center);
          }
          expect(find.text('6 小时 44 分 30.37 秒'), findsOneWidget);
          expect(tester.takeException(), isNull);
          if (((width == 760 && scale == 1) || (width == 360 && scale == 1.6)) && brightness == Brightness.light) {
            final longField = find.byKey(const ValueKey('maintenance-field-挂载路径'));
            await tester.tap(width == 760
              ? find.descendant(of: longField, matching: find.byType(IconButton))
              : find.text(longValue));
            await tester.pumpAndSettle();
            expect(find.byType(Dialog), findsOneWidget);
            final detail = find.descendant(of: find.byType(Dialog), matching: find.byType(SelectableText));
            expect(tester.widget<SelectableText>(detail).data, longValue);
            await tester.tap(find.byTooltip('复制')); await tester.pumpAndSettle();
            expect(copied, longValue);
            await tester.tap(find.byTooltip('关闭')); await tester.pumpAndSettle();
            expect(find.byType(Dialog), findsNothing);
            expect(tester.takeException(), isNull);
          }
          await tester.pumpWidget(const SizedBox());
        }
      }
    }
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('运维卡片退场保留视图，快速恢复保留展开状态且结束后释放', (tester) async {
    await tester.runAsync(() => _testSettings.updateDialogAnimationSettings(const DialogAnimationSettings(
      durationMs: 600, curve: DialogAnimationCurve.easeInOut,
      entranceStyle: DialogAnimationStyle.fadeScale, exitStyle: DialogAnimationStyle.fadeScale)));
    for (final mode in ['列表', '网格', '分组']) {
      var visible = true;
      late StateSetter update;
      await tester.pumpWidget(MaterialApp(locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: StatefulBuilder(builder: (context, setState) {
          update = setState;
          final children = <Widget>[
            if (visible) const _MaintenanceSection(key: ValueKey('动态板块'), title: '可展开卡片', child: Text('保留展开内容')),
            const _MaintenanceCard(key: ValueKey('固定板块'), title: '固定卡片', child: Text('固定内容')),
          ];
          return switch (mode) {
            '列表' => _MaintenanceAnimatedList(children: children),
            '网格' => SingleChildScrollView(child: _MaintenanceGrid(maxColumns: 1, children: children)),
            _ => SingleChildScrollView(child: _MaintenanceAnimatedColumn(spacing: 12, children: children)),
          };
        }))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('可展开卡片')); await tester.pumpAndSettle();
      final tileState = tester.state(find.byType(ExpansionTile));
      update(() => visible = false); await tester.pump(); await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('保留展开内容'), findsOneWidget, reason: mode);
      expect(find.text('可展开卡片').hitTestable(), findsNothing, reason: mode);
      update(() => visible = true); await tester.pump(); await tester.pumpAndSettle();
      expect(identical(tileState, tester.state(find.byType(ExpansionTile))), isTrue, reason: mode);
      expect(find.text('保留展开内容'), findsOneWidget, reason: mode);
      update(() => visible = false); await tester.pump(); await tester.pumpAndSettle();
      expect(find.text('可展开卡片'), findsNothing, reason: mode);
      expect(find.text('固定内容'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('单向禁用分别控制卡片进场与退场', (tester) async {
    for (final entranceDisabled in [true, false]) {
      await tester.runAsync(() => _testSettings.updateDialogAnimationSettings(DialogAnimationSettings(
        durationMs: 600, entranceStyle: entranceDisabled ? DialogAnimationStyle.none : DialogAnimationStyle.fade,
        exitStyle: entranceDisabled ? DialogAnimationStyle.fade : DialogAnimationStyle.none)));
      var visible = false;
      late StateSetter update;
      await tester.pumpWidget(MaterialApp(locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: StatefulBuilder(builder: (context, setState) {
          update = setState;
          return _MaintenanceAnimatedList(children: [if (visible)
            const _MaintenanceCard(key: ValueKey('单向'), title: '单向卡片', child: Text('内容'))]);
        }))));
      await tester.pumpAndSettle();
      update(() => visible = true); await tester.pump(); await tester.pump(const Duration(milliseconds: 60));
      final fades = tester.widgetList<FadeTransition>(find.ancestor(of: find.text('单向卡片'), matching: find.byType(FadeTransition)));
      expect(fades.any((fade) => fade.opacity.value < .99), !entranceDisabled);
      await tester.pumpAndSettle();
      update(() => visible = false); await tester.pump(); await tester.pump(const Duration(milliseconds: 60));
      expect(find.text('单向卡片'), entranceDisabled ? findsOneWidget : findsNothing);
      await tester.pumpAndSettle(); expect(find.text('单向卡片'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('卡片内容增长与缩短经过中间尺寸，刷新不重新挂载卡片', (tester) async {
    await tester.runAsync(() => _testSettings.updateDialogAnimationSettings(const DialogAnimationSettings(
      durationMs: 600, curve: DialogAnimationCurve.easeInOut)));
    var height = 40.0;
    late StateSetter update;
    await tester.pumpWidget(MaterialApp(locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: StatefulBuilder(builder: (context, setState) {
        update = setState;
        return SingleChildScrollView(child: _MaintenanceGrid(maxColumns: 1, children: [
          _MaintenanceCard(key: const ValueKey('尺寸卡片'), title: '动态内容', scrollBody: false, child: SizedBox(height: height)),
          const _MaintenanceCard(key: ValueKey('相邻卡片'), title: '相邻内容', child: SizedBox(height: 40)),
        ]));
      }))));
    await tester.pumpAndSettle();
    final card = find.byKey(const ValueKey('尺寸卡片'));
    final before = tester.getSize(card).height;
    final element = tester.element(card);
    update(() => height = 200); await tester.pump(); await tester.pump(const Duration(milliseconds: 160));
    final growing = tester.getSize(card).height;
    expect(growing, greaterThan(before)); expect(growing, lessThan(before + 160));
    expect(tester.getRect(find.byKey(const ValueKey('相邻卡片'))).top, greaterThanOrEqualTo(tester.getRect(card).bottom + 11.9));
    await tester.pumpAndSettle();
    final expanded = tester.getSize(card).height;
    expect(expanded, closeTo(before + 160, .01));
    expect(identical(element, tester.element(card)), isTrue);
    update(() => height = 40); await tester.pump(); await tester.pump(const Duration(milliseconds: 160));
    expect(tester.getSize(card).height, greaterThan(before));
    expect(tester.getSize(card).height, lessThan(expanded));
    await tester.pumpAndSettle(); expect(tester.getSize(card).height, closeTo(before, .01));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('网格换列与字段增删遵循弹性设置，关闭动效和减少动画立即收敛', (tester) async {
    await tester.runAsync(() => _testSettings.updateDialogAnimationSettings(const DialogAnimationSettings(
      durationMs: 600, curve: DialogAnimationCurve.elasticOut,
      entranceStyle: DialogAnimationStyle.springScale, exitStyle: DialogAnimationStyle.springScale)));
    var width = 760.0;
    var count = 3;
    var reduced = false;
    var ticker = true;
    late StateSetter update;
    await tester.pumpWidget(MaterialApp(locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: StatefulBuilder(builder: (context, setState) {
        update = setState;
        return MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
          child: TickerMode(enabled: ticker, child: SingleChildScrollView(child: Align(alignment: Alignment.topLeft, child: SizedBox(width: width,
            child: _MaintenanceGrid(minWidth: 300, maxColumns: 2, children: [
              for (var i = 0; i < count; i++) _MaintenanceCard(key: ValueKey(i), title: '设备 ' + i.toString(), scrollBody: false,
                child: _MaintenanceFields(rows: [['状态', '运行'], if (count > 1) ['名称', '设备']])),
            ]))))));
      }))));
    await tester.pumpAndSettle();
    update(() { width = 360; count = 2; }); await tester.pump();
    for (var frame = 0; frame < 12; frame++) {
      await tester.pump(const Duration(milliseconds: 60));
      expect(tester.takeException(), isNull);
      for (final element in find.byType(_MaintenanceCard).evaluate()) {
        final rect = tester.getRect(find.byWidget(element.widget));
        expect(rect.width.isFinite && rect.height.isFinite, isTrue);
        expect(rect.width, greaterThanOrEqualTo(0));
      }
    }
    await tester.pumpAndSettle(); expect(find.text('设备 2'), findsNothing);
    expect(tester.getRect(find.byKey(const ValueKey(1))).top, greaterThan(tester.getRect(find.byKey(const ValueKey(0))).bottom));
    update(() { count = 1; reduced = true; }); await tester.pump(); await tester.pump();
    expect(find.text('设备 1'), findsNothing);
    expect(find.text('名称'), findsNothing);
    update(() { count = 2; reduced = false; }); await tester.pumpAndSettle();
    update(() { count = 1; ticker = false; }); await tester.pump(); await tester.pump();
    expect(find.text('设备 1'), findsNothing);
    update(() { ticker = true; count = 2; }); await tester.pumpAndSettle();
    update(() => count = 1); await tester.pump(); await tester.pump(const Duration(milliseconds: 60));
    await tester.runAsync(() => _testSettings.updateDialogAnimationSettings(OpenHandMotionDefaults.disabled));
    await tester.pump(); await tester.pump();
    expect(find.text('设备 1'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('诊断与元数据折叠标题统一高度，动效遵循全局设置并保留展开状态', (tester) async {
    await tester.binding.setSurfaceSize(const Size(760, 900));
    Widget screen(double scale) => MaterialApp(locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
      home: const Scaffold(body: SingleChildScrollView(child: Column(children: [
        _MaintenanceSection(title: '采集详情与诊断', icon: Icons.fact_check_outlined, child: Text('权限诊断')),
        _MaintenanceSection(title: '运行时元数据与状态', subtitle: '已采集', child: Text('运行时字段')),
        _MaintenanceSection(title: 'GPU 组件指标', subtitle: '24 项指标', child: Text('GPU 字段')),
      ]))));
    final tiles = find.byType(ExpansionTile);
    for (final scale in [1.0, 1.6]) {
      await tester.pumpWidget(screen(scale)); await tester.pumpAndSettle();
      final heights = [for (final tile in tiles.evaluate()) tester.getSize(find.byWidget(tile.widget)).height];
      for (final height in heights) expect(height, closeTo(heights.first, .01));
      expect(tester.takeException(), isNull);
    }
    for (final tile in tester.widgetList<ExpansionTile>(tiles)) {
      expect(tile.expansionAnimationStyle!.duration, _testSettings.dialogAnimationSettings.entranceDuration);
      expect(tile.expansionAnimationStyle!.reverseDuration, _testSettings.dialogAnimationSettings.exitDuration);
    }
    await tester.tap(find.text('运行时元数据与状态')); await tester.pumpAndSettle();
    expect(find.text('运行时字段'), findsOneWidget);
    await tester.runAsync(() => _testSettings.updateDialogAnimationSettings(OpenHandMotionDefaults.disabled));
    await tester.pumpAndSettle();
    for (final tile in tester.widgetList<ExpansionTile>(tiles)) {
      expect(tile.expansionAnimationStyle!.duration, Duration.zero);
      expect(tile.expansionAnimationStyle!.reverseDuration, Duration.zero);
    }
    expect(find.text('运行时字段'), findsOneWidget);
    await tester.tap(find.text('运行时元数据与状态')); await tester.pump();
    expect(find.text('运行时字段'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox()); await tester.binding.setSurfaceSize(null);
  });

  testWidgets('大组元数据按需展开，空报告与权限诊断保持紧凑结构', (tester) async {
    await tester.runAsync(() async {
      for (final entry in {'运维预览字体': Platform.environment['MAINTENANCE_FONT'], 'MaterialIcons': Platform.environment['MAINTENANCE_ICONS'], 'monospace': Platform.environment['MAINTENANCE_TERMINAL_FONT']}.entries) {
        if (entry.value != null) await (FontLoader(entry.key)..addFont(File(entry.value!).readAsBytes().then((bytes) => ByteData.sublistView(bytes)))).load();
      }
    });
    final metadata = jsonEncode({
      'Name': 'docker-engine', 'ServerVersion': '27.5.1', 'OperatingSystem': 'Ubuntu 24.04',
      'ContainersRunning': 12, 'ContainersPaused': 0, 'ContainersStopped': 3,
      'NetworkSettings': {'网桥': 'bridge', '网关': '172.17.0.1', 'IPv6': false},
      'Config': {for (var i = 0; i < 20; i++) '配置项 \$i': '配置值 \$i'},
    });
    for (final width in [360.0, 760.0, 1280.0]) {
      await tester.binding.setSurfaceSize(Size(width, 1100));
      final theme = OpenHandTheme.light(OpenHandThemePreset.tundraGreen);
      await tester.pumpWidget(MaterialApp(locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales,
        theme: Platform.environment['MAINTENANCE_FONT'] == null ? theme : theme.copyWith(textTheme: theme.textTheme.apply(fontFamily: '运维预览字体')),
        home: Scaffold(body: RepaintBoundary(key: const ValueKey('元数据布局预览'), child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(children: [
          _MaintenanceSection(title: '运行时元数据与状态', icon: Icons.inventory_2_outlined, initiallyExpanded: true,
            child: _MaintenanceReadout(text: metadata, section: 'container_metadata')),
          const SizedBox(height: 12),
          const _MaintenanceSection(title: '采集详情与诊断', icon: Icons.fact_check_outlined,
            child: _MaintenanceReadout(text: 'You need administrator access to run this tool... exiting!', section: 'diagnostic')),
          const SizedBox(height: 12),
          const _MaintenanceSection(title: '实时资源采样', icon: Icons.monitor_heart_outlined, initiallyExpanded: true,
            child: _MaintenanceReadout(text: '', section: 'container_metrics')),
        ]))))));
      await tester.pumpAndSettle();
      expect(find.text('配置值 0'), findsNothing);
      expect(find.text('暂无可用数据'), findsOneWidget);
      if (Platform.environment['MAINTENANCE_PREVIEW'] != null) {
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('元数据布局预览')));
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('/tmp/maintenance-metadata-layout-\${width.toInt()}.png').writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.ensureVisible(find.text('配置'));
      await tester.tap(find.text('配置')); await tester.pumpAndSettle();
      expect(find.text('配置值 0'), findsOneWidget);
      await tester.ensureVisible(find.text('采集详情与诊断'));
      await tester.tap(find.text('采集详情与诊断')); await tester.pumpAndSettle();
      expect(find.text('读取权限不足'), findsOneWidget);
      expect(find.byType(OpenHandConsoleText), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('跨平台网络详情按网卡和协议分组，宽窄窗口与明暗主题无溢出', (tester) async {
    final samples = <(String, String, String)>[
      ('listeners', 'tcp LISTEN 0 128 0.0.0.0:22 0.0.0.0:*\\nUDP [::]:5353 *:* 44', '0.0.0.0:22'),
      ('proxy', '__OH_PROXY_SCOPE__\\t系统设置\\n HTTPEnable : 1\\n HTTPProxy : proxy.example', 'HTTP / 代理状态'),
      ('firewall_status', '应用防火墙:\\n状态: 启用\\nPF:\\n状态: 读取权限不足', '读取权限不足'),
      ('addresses', 'en0: flags=8863<UP,BROADCAST,RUNNING> mtu 1500\\n  ether 02:00:00:00:00:01\\n  inet 192.168.1.2 netmask 0xffffff00\\n  status: active', 'IPv4 地址'),
      ('addresses', '2: eth0: <UP,BROADCAST> mtu 1500 state UP\\n  inet 10.0.0.2/24 scope global eth0\\n  RX: bytes packets errors dropped\\n      1234 10 1 0', '接收 · 字节'),
      ('addresses', 'Ethernet adapter Ethernet:\\n   Physical Address. . . . . . . . . : AA-BB-CC-DD-EE-FF\\n   IPv4 Address. . . . . . . . . . . : 192.168.1.2', 'MAC 地址'),
      ('neighbors', 'Neighbor Linklayer Address Netif Expire St Flgs Prbs\\nfe80::1%lo0 (incomplete) lo0 permanent R', '邻居地址'),
      ('network_stats', 'TCP: inuse 2 orphan 0 tw 4 alloc 12 mem 0\\nUdp:\\n  12 datagrams received', 'TCP 协议统计'),
      ('firewall_rules', 'Rule Name: Web\\nEnabled: Yes\\nDirection: In\\nAction: Allow\\nRule Name: SSH\\nEnabled: Yes\\nDirection: In\\nLocalPort: 22', 'SSH'),
    ];
    for (final brightness in Brightness.values) {
      for (final width in [360.0, 1200.0]) {
        await tester.binding.setSurfaceSize(Size(width, 900));
        for (final sample in samples) {
          final theme = brightness == Brightness.light ? OpenHandTheme.light(OpenHandThemePreset.tundraGreen) : OpenHandTheme.dark(OpenHandThemePreset.tundraGreen);
          await tester.pumpWidget(MaterialApp(locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales,
            theme: Platform.environment['MAINTENANCE_FONT'] == null ? theme : theme.copyWith(textTheme: theme.textTheme.apply(fontFamily: '运维预览字体')),
            home: Scaffold(body: RepaintBoundary(key: const ValueKey('网络结构化预览'), child: SingleChildScrollView(child: _MaintenanceReadout(section: sample.\$1, text: sample.\$2))))));
          await tester.pumpAndSettle();
          expect(find.text(sample.\$3), findsWidgets);
          expect(find.byType(OpenHandConsoleText), findsNothing);
          expect(find.textContaining('flags=8863'), findsNothing);
          expect(tester.takeException(), isNull, reason: sample.\$1);
          if (Platform.environment['MAINTENANCE_PREVIEW'] != null && brightness == Brightness.light && sample.\$2.startsWith('en0:')) {
            await tester.runAsync(() async {
              final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('网络结构化预览')));
              final image = await boundary.toImage();
              final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
              await File('/tmp/maintenance-network-structured-\${width.toInt()}.png').writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          await tester.pumpWidget(const SizedBox());
        }
      }
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('空连接表头与空采样显示空态，容器嵌套元数据完整显示字段路径', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    for (final sample in <(String, String)>[
      ('sockets', 'Active Multipath Internet connections\\nProto/ID Flags Local Address Foreign Address (state)'),
      ('container_metrics', ''),
    ]) {
      await tester.pumpWidget(MaterialApp(locale: const Locale('zh'), localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: SingleChildScrollView(child: _MaintenanceReadout(section: sample.\$1, text: sample.\$2)))));
      await tester.pumpAndSettle();
      expect(find.text('暂无可用数据'), findsOneWidget);
      expect(find.byType(OpenHandConsoleText), findsNothing);
    }
    await tester.pumpWidget(MaterialApp(locale: const Locale('zh'), localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: SingleChildScrollView(child: _MaintenanceReadout(section: 'container_details',
        text: '[{"Name":"worker","State":{"Status":"running","ExitCode":0},"Mounts":[{"Source":"/data","Destination":"/app"}]}]')))));
    await tester.pumpAndSettle();
    expect(find.text('状态 / 状态'), findsOneWidget);
    expect(find.text('/data'), findsOneWidget);
    expect(find.text('/app'), findsOneWidget);
    expect(find.textContaining('{"Name"'), findsNothing);
    expect(find.byType(OpenHandConsoleText), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('SNTP 超时诊断显示结果和目标地址，不渲染十六进制或无效偏移', (tester) async {
    const raw = '@@OH_TIME:SNTP 只读测量\\nsntp_exchange {\\n result: 6 (Timeout)\\n offset: FFFFFFFF (-1999861048.013298512)\\n delay: FFFFFFFF (-3999722096.026597023)\\n addr: 17.253.114.35\\n}\\n@@OH_RESULT:69';
    await tester.binding.setSurfaceSize(const Size(420, 900));
    await tester.pumpWidget(MaterialApp(locale: const Locale('zh'), localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: _MaintenanceHealthContent(
        report: MachineHealthReport.parse('ntp', raw, '0'), raw: raw)))));
    await tester.pumpAndSettle();
    expect(find.textContaining('请求超时'), findsOneWidget);
    expect(find.text('17.253.114.35'), findsOneWidget);
    expect(find.textContaining('FFFFFFFF'), findsNothing);
    expect(find.textContaining('-1999861048'), findsNothing);
    final diagnostic = find.text('采集详情与诊断');
    await tester.ensureVisible(diagnostic);
    await tester.tap(diagnostic); await tester.pumpAndSettle();
    expect(find.text('响应超时'), findsOneWidget);
    expect(find.byType(OpenHandConsoleText), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('防火墙混合输出结构化显示设置与读取权限', (tester) async {
    await tester.binding.setSurfaceSize(const Size(520, 700));
    const raw = 'Firewall is disabled. (State = 0)\\npfctl: /dev/pf: Permission denied';
    await tester.pumpWidget(MaterialApp(locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: SingleChildScrollView(child: _MaintenanceReadout(section: 'firewall', text: raw)))));
    await tester.pumpAndSettle();
    expect(find.text('应用防火墙'), findsOneWidget);
    expect(find.text('禁用'), findsOneWidget);
    expect(find.textContaining('权限不足，当前账户无法读取规则'), findsOneWidget);
    expect(find.textContaining('扩展指标'), findsNothing);
    expect(find.byType(OpenHandConsoleText), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('容器连接错误显示原因、连接地址和处理建议', (tester) async {
    await tester.binding.setSurfaceSize(const Size(520, 700));
    const raw = 'failed to connect to the docker API at unix:///tmp/docker.sock: connect: no such file or directory';
    await tester.pumpWidget(MaterialApp(locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: SingleChildScrollView(child: _MaintenanceReadout(section: 'containers', text: raw)))));
    await tester.pumpAndSettle();
    expect(find.text('容器服务暂不可用'), findsOneWidget);
    expect(find.textContaining('扩展指标'), findsNothing);
    expect(find.text('unix:///tmp/docker.sock'), findsOneWidget);
    expect(find.text('连接未建立'), findsOneWidget);
    expect(find.byType(OpenHandConsoleText), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('长字段保留字号，自定义单元格有全文提示且文本不误缩写', (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 700));
    final long = List.filled(30, 'abcdef0123456789').join(' ');
    await tester.pumpWidget(MaterialApp(locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: _MaintenanceTable(headers: const ['名称', '数值'], rows: [
        OpenHandOperationalRankRow(value: 0, cells: ['记录', long], cellWidgets: [null,
          Text(long, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14))]),
      ]))));
    await tester.pumpAndSettle();
    expect(find.byType(FittedBox), findsNothing);
    final text = find.text(long).first;
    expect(tester.widget<Text>(text).style!.fontSize, 14);
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(text));
    await tester.pumpAndSettle();
    expect(find.text('完整内容'), findsOneWidget);
    await mouse.removePointer();
    for (final raw in ['2026-09-30 08:00:00', '68450 00102 00000100', '65536 Cursor Helper']) {
      await tester.pumpWidget(MaterialApp(locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: _MaintenanceNumber(raw: raw))));
      await tester.pumpAndSettle();
      expect(find.text(raw), findsOneWidget);
      expect(find.byType(InkWell), findsNothing);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('网格末行填满可用宽度且网络诊断没有空白占位', (tester) async {
    for (final width in [420.0, 900.0, 1300.0]) {
      await tester.binding.setSurfaceSize(Size(width, 1000));
      for (final count in [1, 2, 3, 4, 5, 7]) {
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: _MaintenanceGrid(
          minWidth: 300,
          children: [for (var i = 0; i < count; i++)
            Container(key: ValueKey(i), height: 40.0 + i * 5, color: Colors.green)],
        ))));
        await tester.pumpAndSettle();
        final rows = <double, List<Rect>>{};
        for (var i = 0; i < count; i++) {
          final rect = tester.getRect(find.byKey(ValueKey(i)));
          (rows[rect.top] ??= []).add(rect);
        }
        for (final row in rows.values) {
          expect(row.first.left, closeTo(0, .1));
          expect(row.last.right, closeTo(width, .1));
          for (final rect in row) expect(rect.height, closeTo(row.first.height, .1));
        }
        expect(tester.takeException(), isNull);
      }
    }
    await tester.binding.setSurfaceSize(const Size(1280, 1000));
    final service = _MaintenanceFixture();
    await tester.pumpWidget(ChangeNotifierProvider<MachineTerminalFileService>.value(
      value: service,
      child: const MaterialApp(locale: Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: _MachineMaintenanceDialog(sessionId: '会话', terminalId: '终端')))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('网络与诊断'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byWidgetPredicate((w) => w is _MaintenanceCard && w.title == 'DNS 服务器'), 240,
      scrollable: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first,
    );
    await tester.pumpAndSettle();
    final grids = tester.widgetList<_MaintenanceGrid>(find.byType(_MaintenanceGrid));
    final details = grids.singleWhere((grid) => grid.maxColumns == 2 && grid.children.every((child) => child is _MaintenanceCard));
    expect(details.children.length, 2);
    expect(details.children.every((child) => child is _MaintenanceCard), isTrue);
    final rects = [for (final child in details.children) tester.getRect(find.byWidget(child))];
    final layoutRows = <double, List<Rect>>{};
    for (final rect in rects) (layoutRows[rect.top] ??= []).add(rect);
    final bounds = tester.getRect(find.byWidget(details));
    double? previousBottom;
    for (final row in layoutRows.values) {
      expect(row.first.left, closeTo(bounds.left, .1));
      expect(row.last.right, closeTo(bounds.right, .1));
      if (previousBottom != null) expect(row.first.top - previousBottom, closeTo(_maintenanceGridGap, .1));
      previousBottom = row.first.bottom;
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('详情短字段与嵌套字段保持统一宽度和对齐', (tester) async {
    for (final width in [480.0, 900.0]) {
      await tester.binding.setSurfaceSize(Size(width, 1000));
      await tester.pumpWidget(MaterialApp(locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: SingleChildScrollView(child: _MaintenanceReadout(
          text: 'Name: worker\\nOptions: {\\n x = 1;\\n}\\nPID: 42\\nUser: test\\nPath: /tmp\\nConfig: {\\n y = 2;\\n}\\nEnd: done', section: 'status')))));
      await tester.pumpAndSettle();
      final fields = find.byWidgetPredicate((widget) => widget is AnimatedContainer && widget.key is ValueKey<String> && (widget.key as ValueKey<String>).value.startsWith('maintenance-field-'));
      final rows = <double, List<Rect>>{};
      final rects = [for (final element in fields.evaluate()) tester.getRect(find.byWidget(element.widget))];
      for (final rect in rects) {
        (rows[rect.top] ??= []).add(rect);
        expect(rect.width, closeTo(rects.first.width, .1));
        expect(rect.height, closeTo(rects.first.height, .1));
      }
      for (final row in rows.values) {
        expect(row.first.left, closeTo(0, .1));
        expect(row.last.right, lessThanOrEqualTo(width + .01));
        for (var i = 1; i < row.length; i++) expect(row[i].left - row[i - 1].right, closeTo(_maintenanceGridGap, .1));
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('详情固定字段完整展示，无分页、顶部冗余间距或等高空白', (tester) async {
    final font = Platform.environment['MAINTENANCE_FONT'];
    if (font != null) {
      await tester.runAsync(() async {
        final loader = FontLoader('运维详情字体')..addFont(File(font).readAsBytes().then((bytes) => ByteData.sublistView(bytes)));
        await loader.load();
      });
    }
    for (final width in [1100.0, 480.0]) {
      await tester.binding.setSurfaceSize(Size(width, 900));
      await tester.pumpWidget(MaterialApp(locale: const Locale('zh'),
        theme: ThemeData(fontFamily: font == null ? null : '运维详情字体', colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff53651a))),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: RepaintBoundary(key: const ValueKey('详情预览'),
          child: _MachineMaintenanceDetails(title: 'com.example.worker', actions: const {},
            execute: (_) async => '',
            load: () async => '__OH_OPS_platform__\\nDarwin\\n__OH_OPS_status__\\n{\\n"Label" = "com.example.worker";\\n"MachServices" = {\\n "com.example.worker" = true;\\n};\\n}\\n__OH_OPS_memory__\\nDate/Time: 2026-09-30 08:00:00 +0800\\nPhysical footprint: 430.1M\\n__OH_OPS_end__\\n')))));
      await tester.pumpAndSettle();
      expect(find.byType(_MaintenanceTable), findsNothing);
      expect(find.byType(OpenHandTablePagination), findsNothing);
      expect(find.byType(_MaintenanceGrid), findsNothing);
      expect(find.text('2026-09-30 08:00:00'), findsOneWidget);
      expect(find.text('{'), findsNothing);
      expect(find.text('Mach 服务 / com.example.worker'), findsOneWidget);
      expect(find.text('启用'), findsOneWidget);
      expect(find.textContaining('= true;'), findsNothing);
      final header = tester.getRect(find.byType(_MachineTerminalDialogHeader));
      final cards = find.byType(_MaintenanceCard);
      expect(tester.getRect(cards.first).top - header.bottom, lessThanOrEqualTo(8));
      expect(tester.getRect(cards.last).top - tester.getRect(cards.first).bottom, closeTo(12, 1));
      expect(tester.takeException(), isNull);
      if (width == 1100 && Platform.environment['MAINTENANCE_PREVIEW'] != null) {
        await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('详情预览')));
        final image = await boundary.toImage(pixelRatio: 1.5);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('/tmp/maintenance-details-preview.png').writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox());
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('二级详情结构化展示适配窄窗口与六种语言', (tester) async {
    final fixtures = <String, String>{
      'proxy': '__OH_PROXY_SCOPE__\\t系统设置\\n HTTPEnable : 1\\n HTTPProxy : proxy.example',
      'firewall_status': '应用防火墙:\\n状态: 禁用',
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
        if (fixture.key == 'proxy' || fixture.key == 'firewall_status') {
          final l10n = AppLocalizations.of(tester.element(find.byType(_MaintenanceReadout).first))!;
          if (fixture.key == 'proxy') {
            expect(find.text('HTTP / ' + l10n.maintenanceNetworkProxyState), findsOneWidget);
            expect(find.text(l10n.maintenanceDetailEnabled), findsOneWidget);
            expect(find.text('proxy.example'), findsOneWidget);
          } else {
            expect(find.text(l10n.maintenanceNetworkApplicationFirewall), findsOneWidget);
            expect(find.text(l10n.maintenanceDetailDisabled), findsOneWidget);
          }
        }
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
          if (label == '系统服务' && width == 1280 && brightness == Brightness.light && Platform.environment['MAINTENANCE_PREVIEW'] != null) {
            final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('运维预览')));
            await tester.runAsync(() async {
              final image = await boundary.toImage();
              final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
              await File(Platform.environment['MAINTENANCE_PREVIEW']! + '.services.png').writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          if (label == '网络与诊断' && width == 1280 && brightness == Brightness.light && Platform.environment['MAINTENANCE_PREVIEW'] != null) {
            await tester.ensureVisible(find.text('网络吞吐').last);
            await tester.pumpAndSettle();
            await tester.runAsync(() async {
              final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('运维预览')));
              final image = await boundary.toImage();
              final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
              await File(Platform.environment['MAINTENANCE_PREVIEW']! + '.network-panels.png').writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
            final scroll = tester.state<ScrollableState>(find.descendant(of: find.byType(CustomScrollView).first, matching: find.byType(Scrollable)).first);
            scroll.position.jumpTo(scroll.position.maxScrollExtent);
            await tester.pumpAndSettle();
            await tester.runAsync(() async {
              final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('运维预览')));
              final image = await boundary.toImage();
              final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
              await File(Platform.environment['MAINTENANCE_PREVIEW']! + '.network.png').writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
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
        for (final element in field.evaluate().toList()) {
        final currentField = find.byWidget(element.widget);
        await tester.ensureVisible(currentField);
        await tester.tap(currentField);
        await tester.pumpAndSettle();
        final decorator = tester.widget<InputDecorator>(find.descendant(of: currentField, matching: find.byType(InputDecorator)));
        expect(decorator.isFocused, isTrue);
        final decoration = decorator.decoration.applyDefaults(Theme.of(tester.element(currentField)).inputDecorationTheme);
        for (final border in [decoration.border, decoration.enabledBorder, decoration.disabledBorder,
          decoration.focusedBorder, decoration.errorBorder, decoration.focusedErrorBorder]) {
          expect(border, isA<OutlineInputBorder>());
          expect((border! as OutlineInputBorder).borderRadius, BorderRadius.circular(10));
        }
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        }
      }
      await tester.pumpWidget(const SizedBox());
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('服务列表按 PID 关联进程指标，采样失败提示且恢复后清除', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1100));
    for (final locale in AppLocalizations.supportedLocales) {
      final service = _MaintenanceFixture()..platform = 'Darwin';
      await tester.pumpWidget(ChangeNotifierProvider<MachineTerminalFileService>.value(value: service,
        child: MaterialApp(locale: locale, localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: _MachineMaintenanceDialog(sessionId: '会话', terminalId: '终端')))));
      await tester.pumpAndSettle();
      final state = tester.state<_MachineMaintenanceDialogState>(find.byType(_MachineMaintenanceDialog));
      final data = {
        'platform': 'Darwin', 'manager': 'launchd',
        'services': 'com.example.running\\t42\\t0\\ncom.example.idle\\t-\\t0\\ncom.example.zero\\t0\\t0\\ncom.example.gone\\t99\\t0\\ncom.example.unknownMemory\\t7\\t0',
        'service_processes': '42\\treader\\t2.5\\t1024\\t01:23\\t1:02.30\\t/Applications/Example App/run --flag value\\n7\\troot\\t0.0\\tinvalid\\t00:10\\t0:00.00\\t/example\\n错误信息\\n99\\t截断记录',
        'service_processes_status': 'ok',
      };
      void show(Map<String, String> sample) => state.setState(() {
        state._automatic = false; state._tab = 2; state._snapshots[2] = MachineMaintenanceSnapshot(sample);
      });
      _MaintenanceTable table() => tester.widgetList<_MaintenanceTable>(find.byType(_MaintenanceTable))
          .firstWhere((w) => w.headers.contains('累计 CPU 时间'));
      show(data); await tester.pumpAndSettle();
      final rows = {for (final row in table().rows) row.cells.first: row.cells};
      expect(rows['com.example.running']!.skip(4).toList(),
          ['reader', '2.5%', '1 MB', '01:23', '1:02.30', '/Applications/Example App/run --flag value']);
      expect(rows['com.example.idle']!.skip(4), everyElement('—'));
      expect(rows['com.example.zero']!.skip(4), everyElement('—'));
      expect(rows['com.example.zero']![1], rows['com.example.idle']![1]);
      expect(rows['com.example.gone']!.skip(4), everyElement('—'));
      expect(rows['com.example.unknownMemory']![6], '—');
      final warning = lookupAppLocalizations(locale).maintenanceServiceMetricsUnavailable;
      expect(find.text(warning), findsNothing);
      for (final status in ['failed', 'partial']) {
        show({...data, 'service_processes_status': status}); await tester.pumpAndSettle();
        expect(find.text(warning), findsOneWidget);
        expect(table().rows.first.cells[4], 'reader');
      }
      show(data); await tester.pumpAndSettle();
      expect(find.text(warning), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('进程工具栏排序与视图切换同行等高，窄屏换行并保留视图状态', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1100));
    final service = _MaintenanceFixture();
    await tester.pumpWidget(ChangeNotifierProvider<MachineTerminalFileService>.value(value: service,
      child: MaterialApp(locale: const Locale('zh'), localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: OpenHandTheme.light(OpenHandThemePreset.values.first).copyWith(textTheme: OpenHandTheme.light(OpenHandThemePreset.values.first).textTheme.apply(fontFamily: Platform.environment['MAINTENANCE_FONT'] == null ? null : '运维预览字体')),
        home: const MediaQuery(data: MediaQueryData(size: Size(1440, 1100)), child: Scaffold(body: _MachineMaintenanceDialog(sessionId: '会话', terminalId: '终端'))))));
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
    final viewToggle = find.byType(SegmentedButton<bool>);
    expect(tester.getSize(viewToggle).height, controlHeight);
    expect(tester.getRect(viewToggle).left - tester.getRect(sortMenu).right, closeTo(8, .01));
    expect(tester.getRect(viewToggle).top, tester.getRect(sortMenu).top);
    expect(tester.getRect(viewToggle).right, closeTo(tester.getRect(find.byKey(const ValueKey('运维进程列表'))).right, 1));
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('/tmp/process-toolbar-preview.png').writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    await tester.tap(find.text('关系树'));
    await tester.pumpAndSettle();
    for (final width in [600.0, 440.0]) {
      await tester.binding.setSurfaceSize(Size(width, 1100));
      await tester.pumpAndSettle();
      final bounds = tester.getRect(find.byKey(const ValueKey('运维进程列表')));
      final sortRect = tester.getRect(sortMenu);
      final toggleRect = tester.getRect(viewToggle);
      expect(toggleRect.height, controlHeight);
      expect(sortRect.height, controlHeight);
      expect(toggleRect.right, closeTo(bounds.right, 1));
      expect(toggleRect.left, greaterThanOrEqualTo(bounds.left));
      expect(sortRect.overlaps(toggleRect), isFalse);
      expect(tester.getRect(search).overlaps(toggleRect), isFalse);
      expect(tester.widget<SegmentedButton<bool>>(viewToggle).selected, {true});
      expect(tester.takeException(), isNull);
    }
    await tester.binding.setSurfaceSize(const Size(1440, 1100));
    await tester.pumpAndSettle();
    await tester.tap(find.text('列表'));
    await tester.pumpAndSettle();
    for (final tab in ['运行总览', '系统服务', '网络与诊断']) {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
      if (tab == '系统服务') {
        final services = tester.widget<_MaintenanceTable>(find.byType(_MaintenanceTable).first);
        expect(services.headers.length, 16);
        expect(services.rows.first.cells.skip(6).take(6).toList(), ['42', '1 MB', '2.00 s', '3', '0', '0']);
        expect(tester.getSize(find.byType(TextField).first).height, controlHeight);
        expect(tester.getSize(find.byType(TextField).first).width, _maintenanceSearchWidth);
        final serviceModes = find.byType(SegmentedButton<bool>);
        final serviceCard = find.ancestor(of: serviceModes, matching: find.byType(_MaintenanceCard));
        expect(tester.getRect(serviceModes).right, closeTo(tester.getRect(serviceCard).right - 11, .01));
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('/tmp/service-header-preview.png').writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        for (final label in ['开机启动状态', '系统定时器']) {
          final button = find.widgetWithText(OutlinedButton, label);
          if (button.evaluate().isNotEmpty) expect(tester.getSize(button).height, controlHeight);
        }
      }
      for (final element in find.byType(_MaintenanceGrid).evaluate()) {
        final grid = element.widget as _MaintenanceGrid;
        final bottoms = <double, double>{};
        for (final child in grid.children) {
          final rect = tester.getRect(find.byWidget(child));
          expect(rect.bottom, closeTo(bottoms.putIfAbsent(rect.top, () => rect.bottom), .01));
        }
      }
      final viewport = find.byType(CustomScrollView).first;
      expect(tester.getRect(viewport).bottom, closeTo(dialogBottom - _maintenancePanelBottomInset, 1));
      await tester.drag(viewport, const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(tester.getRect(viewport).bottom, closeTo(dialogBottom - _maintenancePanelBottomInset, 1));
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('服务与日志手动自动刷新不重叠，失败停止，关闭清理', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    var loads = 0;
    Completer<String>? pending;
    var fail = false;
    const sample = '__OH_OPS_platform__\\nDarwin\\n__OH_OPS_status__\\nstate = running\\n__OH_OPS_logs__\\n服务日志第一行\\n服务日志第二行\\n__OH_OPS_end__\\n';
    await tester.pumpWidget(MaterialApp(locale: const Locale('zh'), localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: _MachineMaintenanceDetails(title: '测试服务', actions: const {}, execute: (_) async => '',
        refreshInterval: const Duration(seconds: 10), load: () async {
          loads++;
          if (fail) throw StateError('模拟服务刷新失败');
          return pending == null ? sample : await pending!.future;
        }))));
    await tester.pumpAndSettle();
    expect(loads, 1);
    await tester.tap(find.byTooltip('查看服务日志'));
    await tester.pumpAndSettle();
    expect(find.byType(_MaintenanceLogTimeline), findsOneWidget);
    await tester.tap(find.byTooltip('刷新服务与日志'));
    await tester.pumpAndSettle();
    expect(loads, 2);
    await tester.tap(find.byTooltip('自动刷新服务与日志（10 秒）'));
    pending = Completer<String>();
    await tester.pump(const Duration(seconds: 11));
    expect(loads, 3);
    await tester.pump(const Duration(seconds: 30));
    expect(loads, 3);
    pending!.complete(sample);
    pending = null;
    await tester.pumpAndSettle();
    fail = true;
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(loads, 4);
    await tester.pump(const Duration(seconds: 30));
    expect(loads, 4);
    expect(find.byTooltip('自动刷新服务与日志（10 秒）'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
    expect(loads, 4);
    expect(tester.takeException(), isNull);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('居中提示在长文案、窄屏与放大文字下保持整体居中', (tester) async {
    for (final width in [320.0, 1200.0]) {
      await tester.binding.setSurfaceSize(Size(width, 700));
      await tester.pumpWidget(MaterialApp(home: MediaQuery(
        data: MediaQueryData(size: Size(width, 700), textScaler: const TextScaler.linear(2)),
        child: const Scaffold(body: Center(child: Padding(
          padding: EdgeInsets.all(24), child: _MaintenanceEmptyHint(
            message: '正在读取详情，请稍候 / Chargement des détails en cours')))))));
      await tester.pump();
      final row = find.descendant(of: find.byType(_MaintenanceEmptyHint), matching: find.byType(Column)).first;
      expect(tester.getCenter(row).dx, closeTo(width / 2, .1));
      expect(tester.getCenter(row).dy, closeTo(350, .1));
      expect(tester.getRect(row).left, greaterThanOrEqualTo(24));
      expect(tester.getRect(row).right, lessThanOrEqualTo(width - 24));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('容器详情首次加载居中，刷新时保留原有数据', (tester) async {
    for (final width in [420.0, 1200.0]) {
      for (final locale in [const Locale('zh'), const Locale('fr')]) {
        await tester.binding.setSurfaceSize(Size(width, 850));
        var pending = Completer<String>();
        await tester.pumpWidget(MaterialApp(locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: _ContainerReportDialog(title: 'worker', load: () => pending.future))));
        await tester.pump();
        final hint = find.byType(_MaintenanceEmptyHint);
        final body = find.ancestor(of: hint, matching: find.byType(Flexible)).first;
        final row = find.descendant(of: hint, matching: find.byType(Column)).first;
        expect(tester.getCenter(row).dx, closeTo(tester.getCenter(body).dx, .1));
        expect(tester.getCenter(row).dy, closeTo(tester.getCenter(body).dy, .1));
        final l = await AppLocalizations.delegate.load(locale);
        expect(find.text(l.maintenanceLoadingDetails), findsOneWidget);
        expect(find.byType(_MaintenanceReadout), findsNothing);
        expect(tester.takeException(), isNull);
        pending.complete('Name: worker');
        await tester.pumpAndSettle();
        expect(find.byType(_MaintenanceReadout), findsOneWidget);
        pending = Completer<String>();
        final state = tester.state<_ContainerReportDialogState>(find.byType(_ContainerReportDialog));
        final refresh = state._load();
        await tester.pump();
        expect(find.byType(_MaintenanceReadout), findsOneWidget);
        expect(find.text(l.maintenanceLoadingDetails), findsNothing);
        pending.complete('Name: updated');
        await refresh;
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    }
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
        expect(progressRect.top, greaterThanOrEqualTo(headerRect.bottom));
        expect(progressRect.left, greaterThanOrEqualTo(headerRect.left));
        final hint = find.byType(_MaintenanceEmptyHint);
        final body = find.ancestor(of: hint, matching: find.byType(Center)).first;
        final hintRow = find.descendant(of: hint, matching: find.byType(Column)).first;
        expect(tester.getCenter(hintRow).dx, closeTo(tester.getCenter(body).dx, .1));
        expect(tester.getCenter(hintRow).dy, closeTo(tester.getCenter(body).dy, .1));
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


  testWidgets('树形按钮保持方形，双卡填满列宽，同行卡片等高', (tester) async {
    await tester.runAsync(() async {
      for (final entry in {'运维预览字体': Platform.environment['MAINTENANCE_FONT'], 'MaterialIcons': Platform.environment['MAINTENANCE_ICONS'], 'monospace': Platform.environment['MAINTENANCE_TERMINAL_FONT']}.entries) {
        if (entry.value != null) await (FontLoader(entry.key)..addFont(File(entry.value!).readAsBytes().then((bytes) => ByteData.sublistView(bytes)))).load();
      }
    });
    await tester.binding.setSurfaceSize(const Size(1100, 850));
    await tester.pumpWidget(MaterialApp(locale: const Locale('zh'), localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales, theme: OpenHandTheme.light(OpenHandThemePreset.values.first).copyWith(textTheme: OpenHandTheme.light(OpenHandThemePreset.values.first).textTheme.apply(fontFamily: Platform.environment['MAINTENANCE_FONT'] == null ? null : '运维预览字体')),
      home: Scaffold(body: RepaintBoundary(key: const ValueKey('树预览'), child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
        _MaintenanceGrid(children: [Container(key: const ValueKey('甲'), height: 40), Container(key: const ValueKey('乙'), height: 40)]),
        _MaintenanceGrid(maxColumns: 2, children: [SizedBox(key: const ValueKey('长卡'), height: 100), SizedBox(key: const ValueKey('短卡'), height: 30), SizedBox(height: 10), SizedBox(key: const ValueKey('续卡'), height: 10)]),
        _MaintenanceBrowser(query: '', nameColumn: 1, parents: const {'2': ['1'], '3': ['2']},
          table: _MaintenanceTable(maxBodyHeight: 450, headers: const ['PID', '进程', '状态', 'CPU', '内存'], rows: [
            OpenHandOperationalRankRow(value: 0, cells: ['1', 'launchd', '运行', '1%', '20 MB']),
            OpenHandOperationalRankRow(value: 0, cells: ['2', '应用进程', '运行', '2%', '120 MB']),
            OpenHandOperationalRankRow(value: 0, cells: ['3', '后台工作进程', '休眠', '0%', '12 MB']),
          ])),
      ]))))));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const ValueKey('甲'))).width, 528);
    expect(tester.getSize(find.byKey(const ValueKey('短卡'))).height, 100);
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

  testWidgets('服务视图切换位于标题行右端，六种语言窄屏可用且保留展开状态', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    for (final locale in [const Locale('zh'), const Locale('zh', 'Hant'), const Locale('en'), const Locale('de'), const Locale('fr'), const Locale('ja')]) {
      await tester.binding.setSurfaceSize(const Size(900, 700));
      await tester.pumpWidget(MaterialApp(
        locale: locale, localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(fontFamily: Platform.environment['MAINTENANCE_FONT'] == null ? null : '运维预览字体'),
        home: Scaffold(body: _MaintenanceBrowser(title: '服务列表', query: '', parents: const {}, groupNames: true,
          table: _MaintenanceTable(headers: const ['名称', '状态', 'PID'], rows: [
            OpenHandOperationalRankRow(value: 0, cells: ['com.apple.test', 'running', '123']),
            OpenHandOperationalRankRow(value: 0, cells: ['com.apple.worker', 'stopped', '—']),
          ])))));
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(_MaintenanceBrowser));
      final l10n = AppLocalizations.of(context)!;
      final modes = find.byType(SegmentedButton<bool>);
      final card = find.byType(_MaintenanceCard);
      final title = find.text(maintenanceLabel(context, '服务列表'));
      expect(tester.getRect(modes).right, closeTo(tester.getRect(card).right - 11, .01));
      expect(tester.getCenter(modes).dy, closeTo(tester.getCenter(title).dy, .01));
      expect(tester.getSize(modes).height, _maintenanceControlHeight);
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
      await tester.binding.setSurfaceSize(const Size(380, 700));
      await tester.pumpAndSettle();
      expect(tester.getRect(modes).right, closeTo(tester.getRect(card).right - 11, .01));
      expect(tester.getRect(modes).overlaps(tester.getRect(title)), isFalse);
      expect(tester.widget<SegmentedButton<bool>>(modes).selected, {true});
      expect(find.text('com.apple.test'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
    await tester.binding.setSurfaceSize(null);
  });


  testWidgets('Apple GPU 首次采样不占空趋势框，基本信息连续排布且保留单位', (tester) async {
    final service = _MaintenanceFixture()..platform = 'Darwin';
    service.gpuOutput = ['__OH_OPS_platform__', 'Darwin', '__OH_OPS_host__', 'GPU主机',
      '__OH_OPS_gpu_apple__', jsonEncode({'SPDisplaysDataType': [{'sppci_model': 'Apple M4', 'sppci_cores': '10', 'spdisplays_vendor': 'Apple', 'sppci_bus': 'builtin'}]}),
      '__OH_OPS_gpu_accelerators__', '+-o GPU "model" = "Apple M4" "Device Utilization %"=49 "Renderer Utilization %"=48 "Tiler Utilization %"=45 "In use system memory"=1053818880 "Alloc system memory"=4864057344 "recoveryCount"=0', '__OH_OPS_end__'].join('\\n');
    await tester.binding.setSurfaceSize(const Size(1440, 1100));
    await tester.pumpWidget(ChangeNotifierProvider<MachineTerminalFileService>.value(value: service,
      child: MaterialApp(builder: (context, child) => LayoutBuilder(builder: (context, constraints) => MediaQuery(data: MediaQuery.of(context).copyWith(size: constraints.biggest), child: child!)), theme: ThemeData(fontFamily: Platform.environment['MAINTENANCE_FONT'] == null ? null : '运维预览字体'), locale: Locale('zh'), localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales, home: const Scaffold(body: RepaintBoundary(key: ValueKey('GPU预览'), child: _MachineMaintenanceDialog(sessionId: '会话', terminalId: '终端'))))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('GPU 管理'));
    await tester.pumpAndSettle();
    expect(find.text('Apple M4'), findsOneWidget);
    expect(find.text('GPU 利用率趋势'), findsNothing);
    expect(find.byType(_MaintenanceFacts), findsOneWidget);
    final factsGrid = tester.widget<_MaintenanceGrid>(find.descendant(of: find.byType(_MaintenanceFacts), matching: find.byType(_MaintenanceGrid)));
    final fieldRows = <double, List<Rect>>{};
    for (final child in factsGrid.children) {
      final rect = tester.getRect(find.byWidget(child));
      (fieldRows[rect.top] ??= []).add(rect);
      expect(rect.height, lessThan(80));
    }
    expect(fieldRows.values.map((row) => row.length), List.filled(6, 2));
    for (final row in fieldRows.values) {
      expect(row.last.right, closeTo(tester.getRect(find.byType(_MaintenanceFacts)).right, .01));
    }
    expect(find.descendant(of: find.byType(_MaintenanceFacts), matching: find.text('GPU 核心数')), findsOneWidget);
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

  testWidgets('字段网格保持连续等宽排布，少量字段不占空列', (tester) async {
    for (final scenario in [
      (380.0, 5, [1, 1, 1, 1, 1]),
      (760.0, 5, [3, 2]),
      (1280.0, 5, [3, 2]),
      (1280.0, 6, [3, 3]),
      (1280.0, 12, [4, 4, 4]),
      (1280.0, 2, [2]),
      (1280.0, 1, [1]),
      (1280.0, 0, <int>[]),
    ]) {
      final (width, count, expectedRows) = scenario;
      await tester.binding.setSurfaceSize(Size(width, 1100));
      await tester.pumpWidget(MaterialApp(locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: SingleChildScrollView(child: _MaintenanceFields(
          rows: [for (var i = 0; i < count; i++) ['字段 \$i', '数值 \$i']],
        )))));
      await tester.pumpAndSettle();
      final layoutRows = <double, List<Rect>>{};
      for (var i = 0; i < count; i++) {
        final rect = tester.getRect(find.byWidgetPredicate((w) => w is AnimatedContainer && w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('maintenance-field-')).at(i));
        (layoutRows[rect.top] ??= []).add(rect);
        expect(rect.width, closeTo(layoutRows.values.first.first.width, .01));
        expect(rect.right, lessThanOrEqualTo(width + .01));
      }
      expect(layoutRows.values.map((row) => row.length), expectedRows);
      for (final row in layoutRows.values) {
        expect(row.first.left, closeTo(0, .01));
        for (var i = 1; i < row.length; i++) {
          expect(row[i].left - row[i - 1].right, closeTo(_maintenanceGridGap, .01));
        }
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('日期列统一格式、保留原始业务数据，跨语言刷新及大字号单行显示', (tester) async {
    const source = '2026-08-18 18:01:59 +0800 CST';
    const name = '2026-08-18T00:00:00Z';
    final data = {'CreatedAt': source};
    for (final locale in AppLocalizations.supportedLocales) {
      for (final scale in [1.0, 1.6]) {
        await tester.binding.setSurfaceSize(Size(scale == 1 ? 1100 : 420, 700));
        final l = await AppLocalizations.delegate.load(locale);
        Widget screen(String created) => MaterialApp(locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(fontFamily: Platform.environment['MAINTENANCE_FONT'] == null ? null : '运维预览字体'),
          builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
          home: Scaffold(body: _MaintenanceTable(headers: [l.maintenanceDetailCreated, l.maintenanceTaskNext, '名称', '累计 CPU 时间'],
            rows: [OpenHandOperationalRankRow(value: 0, rowKey: '记录', data: data,
              cells: [created, 'Thu 2026-10-01 01:02:03 UTC', name, '24270.37 s'])])));
        await tester.pumpWidget(screen(source));
        await tester.pumpAndSettle();
        final state = tester.state(find.byType(OpenHandOperationalRankTable));
        var table = tester.widget<OpenHandOperationalRankTable>(find.byType(OpenHandOperationalRankTable));
        expect(table.rows.single.cells, ['2026-08-18 18:01:59', '2026-10-01 01:02:03', name, '24270.37 s']);
        expect(identical(table.rows.single.data, data), isTrue);
        expect(data['CreatedAt'], source);
        expect(table.rows.single.rowKey, '记录');
        expect(table.minimumColumnWidths[0], closeTo(200 * scale, .01));
        expect(tester.getSize(find.text('2026-08-18 18:01:59')).height, lessThan(32 * scale));
        await tester.pumpWidget(screen('2026-08-18T18:02:00.000Z'));
        await tester.pumpAndSettle();
        table = tester.widget<OpenHandOperationalRankTable>(find.byType(OpenHandOperationalRankTable));
        expect(table.rows.single.cells.first, '2026-08-18 18:02:00');
        expect(identical(tester.state(find.byType(OpenHandOperationalRankTable)), state), isTrue);
        expect(find.text('2026-08-18 18:01:59'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('时长单元格默认易读，点击保留原始精度且不触发行操作', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 800));
    var tapped = 0;
    Widget screen(String raw) => MaterialApp(locale: const Locale('zh'), localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Column(children: [
        _MaintenanceTable(headers: const ['PID', '累计 CPU 时间', '运行时长'],
          rows: [OpenHandOperationalRankRow(value: 0, rowKey: '进程', cells: ['24270', raw, '1-02:03:04'])],
          onRowTap: (_) => tapped++),
        const _MaintenanceFields(fieldKeys: ['CPUUsageNSec', '创建时间'], rows: [['累计 CPU 时间', '2000000000'], ['创建时间', '2026-09-30 12:00:00']]),
      ])));
    await tester.pumpWidget(screen('24270.37 s'));
    await tester.pumpAndSettle();
    expect(find.text('6 小时 44 分 30.37 秒'), findsOneWidget);
    expect(find.text('1 天 2 小时 3 分'), findsOneWidget);
    expect(find.text('2 秒'), findsOneWidget);
    expect(find.text('24270'), findsOneWidget);
    expect(find.text('2026-09-30 12:00:00'), findsOneWidget);
    await tester.tap(find.text('6 小时 44 分 30.37 秒'));
    await tester.pumpAndSettle();
    expect(find.text('24270.37 s'), findsOneWidget);
    expect(tapped, 0);
    await tester.pumpWidget(screen('24271.38 s'));
    await tester.pumpAndSettle();
    expect(find.text('24271.38 s'), findsOneWidget);
    await tester.tap(find.text('24271.38 s'));
    await tester.pumpAndSettle();
    expect(find.text('6 小时 44 分 31.38 秒'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('GPU 组件在未发现显卡时仍可展开查看安装元数据', (tester) async {
    await tester.binding.setSurfaceSize(const Size(520, 900));
    final service = _MaintenanceFixture();
    service.gpuOutput = ['__OH_OPS_platform__', 'Linux', '__OH_OPS_host__', 'GPU主机',
      '__OH_OPS_gpu_stack__', 'CUDA Toolkit\\tversion\\t12.8', 'cuDNN\\tversion\\t9.8',
      '__OH_OPS_gpu_fabric__', 'LoadState=not-found', 'Result=success', 'ActiveState=inactive', 'SubState=dead', 'MemoryCurrent=18446744073709551615',
      '__OH_OPS_gpu_details__', '<nvidia_smi_log><gpu id="GPU-X"><ecc_errors>' +
        List.generate(30, (i) => '<metric_\${i}>\${700 + i}</metric_\${i}>').join() +
        '</ecc_errors><temperature><gpu_temp>42 C</gpu_temp></temperature></gpu></nvidia_smi_log>',
      '__OH_OPS_gpu_dcgm_metrics__', '# GPU SMCLK MEMCLK\\n0 1500 N/A',
      '__OH_OPS_end__'].join('\\n');
    await tester.pumpWidget(ChangeNotifierProvider<MachineTerminalFileService>.value(value: service,
      child: MaterialApp(locale: const Locale('zh'), localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => LayoutBuilder(builder: (context, constraints) => MediaQuery(data: MediaQuery.of(context).copyWith(size: constraints.biggest), child: child!)),
        home: const Scaffold(body: _MachineMaintenanceDialog(sessionId: '会话', terminalId: '终端')))));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('GPU 管理'));
    await tester.tap(find.text('GPU 管理'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('GPU 互联管理服务'));
    await tester.tap(find.text('GPU 互联管理服务')); await tester.pumpAndSettle();
    expect(find.text('成功'), findsOneWidget);
    expect(find.text('未找到'), findsOneWidget);
    expect(find.text('未运行'), findsNWidgets(2));
    expect(find.text('18446744073709551615'), findsNothing);
    expect(find.text('not-found'), findsNothing);
    expect(find.text('success'), findsNothing);
    await tester.ensureVisible(find.text('CUDA Toolkit'));
    expect(find.text('CUDA Toolkit'), findsOneWidget);
    await tester.tap(find.text('CUDA Toolkit'));
    await tester.pumpAndSettle();
    expect(find.text('12.8'), findsOneWidget);
    await tester.ensureVisible(find.text('DCGM 单次遥测'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DCGM 单次遥测'));
    await tester.pumpAndSettle();
    expect(find.byType(OpenHandConsoleText), findsNothing);
    expect(find.text('1500'), findsOneWidget);
    await tester.ensureVisible(find.text('GPU-X'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('GPU-X'));
    await tester.pumpAndSettle();
    final eccGroup = find.byKey(const ValueKey('gpu-GPU-X-ecc_errors'));
    expect(eccGroup, findsOneWidget);
    expect(find.text('729'), findsNothing);
    await tester.ensureVisible(eccGroup);
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: eccGroup, matching: find.byType(ListTile)).first);
    await tester.pumpAndSettle();
    expect(find.text('729'), findsOneWidget);

    expect(find.byType(_MaintenanceFields), findsWidgets);
    expect(find.descendant(of: eccGroup, matching: find.byType(_MaintenanceTable)), findsNothing);
    expect(find.byType(OpenHandTablePagination), findsNothing);
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
    final overview = state._overview(state._snapshots[0]!) as _MaintenanceAnimatedList;
    final disk = overview.children.whereType<_MaintenanceCard>().firstWhere((card) => card.title == '磁盘 IO');
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

  testWidgets('定时任务采集期间切换分区会等待旧请求再刷新', (tester) async {
    for (final returnToServices in [false, true]) {
    final service = _MaintenanceFixture()..taskPending = Completer<String>();
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    await tester.pumpWidget(ChangeNotifierProvider<MachineTerminalFileService>.value(value: service,
      child: const MaterialApp(locale: Locale('zh'), localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: _MachineMaintenanceDialog(sessionId: '会话', terminalId: '终端')))));
    await tester.pumpAndSettle();
    final state = tester.state<_MachineMaintenanceDialogState>(find.byType(_MachineMaintenanceDialog));
    await tester.tap(find.text('系统服务'));
    await tester.pumpAndSettle();
    final taskFinder = find.byType(_MachineScheduledTaskPanel);
    await tester.scrollUntilVisible(taskFinder, 400, scrollable: find.descendant(of: find.byType(CustomScrollView).first, matching: find.byType(Scrollable)).first);
    await tester.pump();
    expect(service.taskCalls, 1);
    expect(state._scheduledTasksBusy, isTrue);
    final count = service.calls;
    await tester.tap(find.text('进程管理'));
    await tester.pump();
    expect(service.calls, count, reason: '旧任务请求尚未结束，不得争抢终端');
    expect(state._scheduledTasksRefreshPending, isTrue);
    if (returnToServices) {
      await tester.tap(find.text('系统服务')); await tester.pumpAndSettle();
      await tester.scrollUntilVisible(taskFinder, 400, scrollable: find.descendant(of: find.byType(CustomScrollView).first, matching: find.byType(Scrollable)).first);
      await tester.pump();
      expect(service.taskCalls, 1, reason: '切回板块时新请求应等待旧请求结束');
    }
    service.taskPending!.complete(taskFixture());
    service.taskPending = null;
    await tester.pumpAndSettle();
    expect(service.calls, count + 1);
    expect(service.lastCommand, contains(returnToServices ? 'section manager' : 'section processes'));
    expect(state._scheduledTasksBusy, isFalse);
    expect(state._scheduledTaskOperations, 0);
    expect(state._scheduledTasksRefreshPending, isFalse);
    expect(state._error, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
    }
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
  Completer<void>? pending;
  @override
  Future<SettingsLoadResult> load() async => SettingsLoadResult(snapshot: snapshot, canPersist: true);
  @override
  Future<void> save(AppSettingsSnapshot value) async {
    await pending?.future;
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

const _scheduledChecks = r'''
String taskRecord(String kind, List<String> fields) => '__OH_TASK__\t$kind\t${fields.map((v) => base64Encode(utf8.encode(v))).join('\t')}\n';
String taskFixture() => '${taskRecord('meta',['tester','UTC +0000','2026-09-30T00:00:00Z'])}${taskRecord('available',['cron'])}${taskRecord('cron',['user:tester','tester','# 保留环境\nCRON_TZ=Asia/Shanghai\n0 9 * * * /opt/backup --daily\n# OPENHAND_DISABLED @hourly /opt/cleanup\n','1'])}__OH_TASK_END__';
void scheduledTaskChecks() {
  testWidgets('定时任务六语言与宽窄屏布局、空态和失败保留', (tester) async {
    final previewKey = GlobalKey();
    for (final locale in AppLocalizations.supportedLocales) {
      for (final width in [1100.0,420.0,320.0]) {
        for (final brightness in Brightness.values) {
          var failed = false;
          await tester.binding.setSurfaceSize(Size(width,1100));
          final scale = width == 320 ? 1.8 : width == 420 ? 1.5 : 1.0;
          final theme = brightness == Brightness.light
              ? OpenHandTheme.light(OpenHandThemePreset.tundraGreen)
              : OpenHandTheme.dark(OpenHandThemePreset.tundraGreen);
          await tester.pumpWidget(_SettingsApp(locale:locale, localizationsDelegates:AppLocalizations.localizationsDelegates,
            supportedLocales:AppLocalizations.supportedLocales,
            theme:theme.copyWith(textTheme:theme.textTheme.apply(fontFamily:Platform.environment['MAINTENANCE_FONT'] == null ? null : '运维预览字体')),
            builder:(context,child)=>MediaQuery(data:MediaQuery.of(context).copyWith(textScaler:TextScaler.linear(scale)),child:child!),
            home:Scaffold(body:RepaintBoundary(key:previewKey,child:SingleChildScrollView(child:_MachineScheduledTaskPanel(
              platform:'Linux', refreshToken:0, onBusy:(_){}, run:(command,cancelled) async {
                if(failed)throw const MachineTaskException('unavailable'); return taskFixture();
              }))))));
          await tester.pumpAndSettle();
          final context=tester.element(find.byType(_MachineScheduledTaskPanel));
          final l=AppLocalizations.of(context)!;
          expect(find.text(l.maintenanceTaskTitle),findsOneWidget);
          expect(find.text('2026-09-30 00:00:00'),findsOneWidget);
          expect(find.text('/opt/backup --daily'),findsWidgets);
          expect(tester.takeException(),isNull);
          final summary = tester.widget<_MaintenanceGrid>(find.byKey(const ValueKey('scheduled-task-summary')));
          final tiles = [for(final child in summary.children) tester.getRect(find.byWidget(child))];
          if(width == 1100) {
            for(final tile in tiles) {
              expect(tile.height, closeTo(tiles.first.height, .1));
              expect(tile.height, lessThan(100));
              expect(tile.top, tiles.first.top);
            }
          }
          final field = find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == l.maintenanceTaskSearch);
          final menu = find.byType(_MaintenanceToolbarMenu<String>);
          expect(tester.getSize(field).height, closeTo(tester.getSize(menu).height,.1));
          final add = find.widgetWithText(FilledButton,l.maintenanceTaskAdd);
          final style = tester.widget<FilledButton>(add).style!;
          expect(style.backgroundColor!.resolve({}), theme.colorScheme.surface.withValues(alpha:.72));
          expect(style.foregroundColor!.resolve({}), theme.colorScheme.onSurfaceVariant);
          final refresh = find.byTooltip(l.maintenanceRefreshSection);
          if(scale==1) {
            expect(tester.getSize(add).height,_maintenanceControlHeight);
            expect(tester.getSize(add).height,closeTo(tester.getSize(refresh).height,.1));
          } else {
            expect(tester.getSize(add).height,greaterThanOrEqualTo(tester.getSize(refresh).height));
          }
          expect(style.elevation!.resolve({WidgetState.hovered}),0);
          expect((style.shape!.resolve({})! as RoundedRectangleBorder).borderRadius,kOpenHandBorderRadius8);
          expect(_taskSchedulerLabel(context,MachineTaskScheduler.cron),l.maintenanceTaskSchedulerCron);
          expect(_taskSchedulerLabel(context,MachineTaskScheduler.systemd),l.maintenanceTaskSchedulerSystemd);
          expect(_taskSchedulerLabel(context,MachineTaskScheduler.launchd),l.maintenanceTaskSchedulerLaunchd);
          expect(_taskFieldLabel(context,'CRON_TZ'),l.maintenanceEgressTimezone);
          expect(_taskFieldLabel(context,'MAILTO'),l.maintenanceTaskMailTo);
          expect(_taskFieldLabel(context,'SHELL'),l.maintenanceShell);
          expect(_taskIssueLabel(context,'systemd/system'),contains(l.maintenanceTaskSchedulerSystemd));
          final mouse = await tester.createGesture(kind:ui.PointerDeviceKind.mouse);
          await mouse.addPointer(location:Offset.zero);await mouse.moveTo(tiles.first.center);await tester.pumpAndSettle();
          for(final box in tester.widgetList<DecoratedBox>(find.descendant(of:find.byKey(const ValueKey('scheduled-task-summary')),matching:find.byType(DecoratedBox)))) {
            if(box.decoration case final BoxDecoration decoration) {
              expect(decoration.gradient,isNull);expect(decoration.boxShadow??[],isEmpty);
            }
          }
          await mouse.removePointer();
          if(locale==const Locale('zh') && Platform.environment['MAINTENANCE_PREVIEW']!=null) {
            await tester.runAsync(() async {
              final boundary=previewKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
              final shot=await boundary.toImage(pixelRatio:1.5); final bytes=await shot.toByteData(format:ui.ImageByteFormat.png);
              await File('/tmp/openhand-scheduled-tasks-' + brightness.name + '-' + width.toInt().toString() + '.png').writeAsBytes(bytes!.buffer.asUint8List()); shot.dispose();
            });
          }
          failed=true;
          await tester.tap(find.byTooltip(l.maintenanceRefreshSection)); await tester.pumpAndSettle();
          expect(find.text('/opt/backup --daily'),findsWidgets);
          expect(find.byType(OpenHandOperationalRowMenu),findsNothing);
          expect(tester.takeException(),isNull);
          await tester.pumpWidget(const SizedBox());
        }
      }
    }
    await tester.binding.setSurfaceSize(null);
  });
  testWidgets('定时任务筛选可回到全部，刷新保留筛选且无结果不丢失摘要', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    var empty = false; var calls = 0; Completer<String>? pending;
    await tester.pumpWidget(_SettingsApp(locale:const Locale('zh'),localizationsDelegates:AppLocalizations.localizationsDelegates,
      supportedLocales:AppLocalizations.supportedLocales,home:Scaffold(body:SingleChildScrollView(child:_MachineScheduledTaskPanel(
        platform:'Linux',refreshToken:0,onBusy:(_){},run:(command,cancelled)async {
          calls++; if(pending!=null)return pending!.future;
          return empty ? '${taskRecord('meta',['tester','UTC','2026-09-30T00:00:00Z'])}__OH_TASK_END__' : taskFixture();
        })))));
    await tester.pumpAndSettle();
    final state=tester.state<_MachineScheduledTaskPanelState>(find.byType(_MachineScheduledTaskPanel));
    final l=AppLocalizations.of(state.context)!;
    Future<void> choose(String label) async {
      await tester.tap(find.byTooltip(l.maintenanceTaskScheduler));await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(PopupMenuItem<String>,label));await tester.pumpAndSettle();
    }
    await choose(l.maintenanceTaskSchedulerCron);expect(state._filter,MachineTaskScheduler.cron);
    await choose(l.maintenanceTaskAll);expect(state._filter,isNull);
    await tester.enterText(find.byWidgetPredicate((w) => w is TextField && w.controller == state._search),'cleanup');await tester.pumpAndSettle();
    final table=tester.widget<_MaintenanceTable>(find.byType(_MaintenanceTable));expect(table.rows.length,1);
    expect(find.text(l.maintenanceTaskTotal),findsOneWidget);
    await tester.enterText(find.byWidgetPredicate((w) => w is TextField && w.controller == state._search),'没有对应任务');await tester.pumpAndSettle();
    expect(find.text(l.maintenanceTaskNoMatches),findsOneWidget);expect(find.byType(_MaintenanceTable),findsNothing);
    await tester.enterText(find.byWidgetPredicate((w) => w is TextField && w.controller == state._search),'');await tester.pumpAndSettle();
    await choose(l.maintenanceTaskSchedulerCron);
    empty=true;await state._refresh();await tester.pumpAndSettle();
    expect(state._filter,MachineTaskScheduler.cron);expect(find.text(l.maintenanceTaskNoMatches),findsOneWidget);
    await choose(l.maintenanceTaskAll);expect(find.text(l.maintenanceTaskEmpty),findsOneWidget);
    pending=Completer<String>();final refresh=state._refresh();await tester.pump();
    final current=calls;await state._refresh();expect(calls,current);
    expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton,Icons.refresh_rounded)).onPressed,isNull);
    pending!.complete(taskFixture());await refresh;pending=null;await tester.pumpAndSettle();
    expect(find.byType(_MaintenanceTable),findsOneWidget);expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox());await tester.binding.setSurfaceSize(null);
  });

  testWidgets('任务编辑失败保留输入，保存仅修改选定配置', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1050,900));
    var attempts=0;
    String? command;
    final snapshot=MachineScheduledTaskSnapshot.parse(taskFixture());
    final client=MachineScheduledTaskClient(platform:'Linux',run:(text) async {
      if(text.contains('task_emit saved')) {
        command=text; attempts++;
        if(attempts==1) return '${taskRecord('error',['save','模拟拒绝'])}__OH_TASK_END__';
        return '__OH_TASK__\tsaved\n__OH_TASK_END__';
      }
      return '__OH_TASK_END__';
    });
    await tester.pumpWidget(_SettingsApp(locale:const Locale('zh'),localizationsDelegates:AppLocalizations.localizationsDelegates,supportedLocales:AppLocalizations.supportedLocales,
      home:Scaffold(body:Builder(builder:(context)=>TextButton(onPressed:()=>showAnimatedDialog<bool>(context:context,builder:(_)=>_MachineTaskDialog(platform:'Linux',snapshot:snapshot,task:snapshot.tasks.first,client:client,edit:true)),child:const Text('打开编辑'))))));
    await tester.tap(find.text('打开编辑')); await tester.pumpAndSettle();
    final state=tester.state<_MachineTaskDialogState>(find.byType(_MachineTaskDialog));
    state._schedule.text='0 10 * * *'; state._command.text='/opt/backup --new';
    await tester.tap(find.text('保存')); await tester.pumpAndSettle();
    await tester.tap(find.text('保存').last); await tester.pumpAndSettle();
    expect(attempts,1); expect(state._command.text,'/opt/backup --new');
    expect(find.textContaining('模拟拒绝'),findsOneWidget);
    await tester.tap(find.text('保存')); await tester.pumpAndSettle();
    await tester.tap(find.text('保存').last); await tester.pumpAndSettle();
    expect(attempts,2); expect(find.byType(_MachineTaskDialog),findsNothing);
    expect(command,contains(base64Encode(utf8.encode('# 保留环境\nCRON_TZ=Asia/Shanghai\n0 10 * * * /opt/backup --new\n# OPENHAND_DISABLED @hourly /opt/cleanup\n'))));
    expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox()); await tester.binding.setSurfaceSize(null);
  });
  testWidgets('定时任务切换时取消未完成读取，关闭不再刷新', (tester) async {
    final pending=Completer<String>(); bool Function()? cancelled; var busy=false;
    await tester.pumpWidget(_SettingsApp(locale:const Locale('zh'),localizationsDelegates:AppLocalizations.localizationsDelegates,supportedLocales:AppLocalizations.supportedLocales,
      home:Scaffold(body:SingleChildScrollView(child:_MachineScheduledTaskPanel(platform:'Linux',refreshToken:0,onBusy:(value)=>busy=value,run:(command,check){cancelled=check;return pending.future;})))));
    await tester.pump(); expect(busy,isTrue); expect(cancelled!(),isFalse);
    await tester.pumpWidget(const SizedBox()); expect(cancelled!(),isTrue); expect(busy,isTrue);
    pending.complete(taskFixture()); await tester.pumpAndSettle(); expect(busy,isFalse); expect(tester.takeException(),isNull);
  });
  testWidgets('定时任务新增弹窗适配六语言窄屏大字号与原生编辑', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420,800));
    final snapshot=MachineScheduledTaskSnapshot.parse(taskFixture());
    for(final locale in AppLocalizations.supportedLocales) {
      for(final platform in ['Linux','Windows']) {
        await tester.pumpWidget(_SettingsApp(locale:locale,
          localizationsDelegates:AppLocalizations.localizationsDelegates,
          supportedLocales:AppLocalizations.supportedLocales,
          builder:(context,child)=>MediaQuery(data:MediaQuery.of(context).copyWith(textScaler:const TextScaler.linear(1.5)),child:child!),
          home:Scaffold(body:Builder(builder:(context)=>TextButton(
            onPressed:()=>showAnimatedDialog<void>(context:context,builder:(_)=>_MachineTaskDialog(
              platform:platform,snapshot:snapshot,task:null,edit:true,
              client:MachineScheduledTaskClient(platform:platform,run:(_)async=>throw StateError('布局验证不得执行远端命令')))),
            child:const Text('打开任务'))))));
        await tester.tap(find.text('打开任务')); await tester.pumpAndSettle();
        final state=tester.state<_MachineTaskDialogState>(find.byType(_MachineTaskDialog));
        final l=AppLocalizations.of(state.context)!;
        expect(find.text(l.maintenanceTaskAdd),findsOneWidget);
        expect(tester.takeException(),isNull);
        if(platform=='Windows') {
          state._name.text='备份任务'; state._command.text=r'C:\Tools & Jobs\backup.exe';
          expect(state._start.text,'2026-10-01T09:00:00');
          await tester.ensureVisible(find.text(l.maintenanceTaskNative));
          await tester.tap(find.text(l.maintenanceTaskNative)); await tester.pumpAndSettle();
          final definition=xml.XmlDocument.parse(state._definition.text);
          expect(definition.findAllElements('Command').single.innerText,state._command.text);
          expect(state._native,isTrue); expect(tester.takeException(),isNull);
        }
        await tester.tap(find.text(l.commonClose)); await tester.pumpAndSettle();
        expect(find.byType(_MachineTaskDialog),findsNothing);
        await tester.pumpWidget(const SizedBox());
      }
    }
    await tester.binding.setSurfaceSize(null);
  });
  testWidgets('任务详情四类调度器六语言分组布局、长路径和明暗大字号可读', (tester) async {
    final snapshot=MachineScheduledTaskSnapshot.parse(taskFixture());
    const source='/System/Library/LaunchAgents/com.example.maintenance.very-long-scheduled-task.plist';
    const command='/usr/local/bin/maintenance-worker --config /Library/Application Support/Example/configuration.json';
    for(final locale in AppLocalizations.supportedLocales) {
      final l=await AppLocalizations.delegate.load(locale);
      for(final scheduler in MachineTaskScheduler.values) {
        for(final width in [1000.0,420.0]) {
          final brightness=width==1000?Brightness.light:Brightness.dark;
          final theme=brightness==Brightness.light?OpenHandTheme.light(OpenHandThemePreset.tundraGreen):OpenHandTheme.dark(OpenHandThemePreset.tundraGreen);
          await tester.binding.setSurfaceSize(Size(width,1000));
          final task=MachineScheduledTask(scheduler:scheduler,id:'test-task',name:'com.example.maintenance.very-long-scheduled-task',
            source:source,definition:'',command:command,owner:'system',state:'running',schedule:scheduler==MachineTaskScheduler.launchd?'259200':'0 9 * * *',
            metadata:const {'StartInterval':'259200','AccuracyUSec':'2000000','UserName':'system'});
          await tester.pumpWidget(_SettingsApp(locale:locale,localizationsDelegates:AppLocalizations.localizationsDelegates,supportedLocales:AppLocalizations.supportedLocales,
            theme:theme.copyWith(textTheme:theme.textTheme.apply(fontFamily:Platform.environment['MAINTENANCE_FONT']==null?null:'运维预览字体')),
            builder:(context,child)=>MediaQuery(data:MediaQuery.of(context).copyWith(size:Size(width,1000),textScaler:TextScaler.linear(width==420?1.6:1)),child:child!),
            home:Scaffold(body:Builder(builder:(context)=>TextButton(onPressed:()=>showAnimatedDialog<void>(context:context,builder:(_)=>RepaintBoundary(
              key:const ValueKey('任务详情预览'),child:_MachineTaskDialog(platform:scheduler==MachineTaskScheduler.windows?'Windows':'Darwin',snapshot:snapshot,task:task,edit:false,
                client:MachineScheduledTaskClient(platform:'Darwin',run:(_)async=>'__OH_TASK_END__')))),child:const Text('打开详情'))))));
          await tester.tap(find.text('打开详情'));await tester.pumpAndSettle();
          final state=tester.state<_MachineTaskDialogState>(find.byType(_MachineTaskDialog));
          expect(find.byType(_MaintenanceFields),findsNothing);
          expect(find.text(l.maintenanceTaskOverview),findsOneWidget);expect(find.text(l.maintenanceTaskExecution),findsOneWidget);
          final path=find.widgetWithText(SelectableText,source);expect(path,findsOneWidget);
          expect(tester.widget<SelectableText>(path).maxLines,isNull);
          expect(find.widgetWithText(SelectableText,command),findsOneWidget);
          expect(_taskFieldValue(state.context,'Program','2h'),'2h');
          expect(_taskFieldValue(state.context,'Result','1234'),'1234');
          final duration=machineMaintenanceReadableDuration('259200 s',languageCode:locale.languageCode,scriptCode:locale.scriptCode)!;
          if(scheduler==MachineTaskScheduler.launchd)expect(find.text(l.maintenanceTaskEvery(duration)),findsOneWidget);
          expect(find.byTooltip(l.maintenanceTaskReadOnly),findsOneWidget);
          expect(find.descendant(of:find.byKey(const ValueKey('task-execution')),matching:find.text(l.maintenanceTaskReadOnly)),findsOneWidget);
          expect(find.byType(_MaintenanceNotice),findsNothing);
          expect(find.text(l.commonDelete),findsNothing);expect(find.text(l.commonEdit),findsNothing);
          final close=find.widgetWithText(OpenHandDialogActionButton,l.commonClose);
          expect(tester.getCenter(close).dx,closeTo(width/2,1));
          final history=find.byKey(const ValueKey('task-history'));
          final expansion=find.descendant(of:history,matching:find.byType(ExpansionTile));
          expect(tester.widget<ExpansionTile>(expansion).initiallyExpanded,isFalse);
          if(width==1000) {
            final overview=tester.getRect(find.byKey(const ValueKey('task-overview')));
            final execution=tester.getRect(find.byKey(const ValueKey('task-execution')));
            expect(overview.height,lessThan(210));expect(execution.height,lessThan(260));
            expect(execution.top-overview.bottom,closeTo(12,1));
          }
          final mouse=await tester.createGesture(kind:ui.PointerDeviceKind.mouse);
          await mouse.addPointer(location:Offset.zero);await mouse.moveTo(tester.getCenter(find.byKey(const ValueKey('task-overview'))));await tester.pumpAndSettle();
          for(final box in tester.widgetList<DecoratedBox>(find.descendant(of:find.byType(_MachineTaskDialog),matching:find.byType(DecoratedBox)))) {
            if(box.decoration case final BoxDecoration decoration) {expect(decoration.gradient,isNull);expect(decoration.boxShadow??[],isEmpty);}
          }
          await mouse.removePointer();expect(tester.takeException(),isNull);
          if(Platform.environment['MAINTENANCE_PREVIEW']!=null&&locale==const Locale('zh')&&scheduler==MachineTaskScheduler.launchd) {
            await tester.runAsync(()async {
              final boundary=tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('任务详情预览')));
              final shot=await boundary.toImage(pixelRatio:1.5);final bytes=await shot.toByteData(format:ui.ImageByteFormat.png);
              await File('/tmp/openhand-task-detail-'+brightness.name+'.png').writeAsBytes(bytes!.buffer.asUint8List());shot.dispose();
            });
          }
          await tester.ensureVisible(find.text(l.maintenanceTaskEnvironment));await tester.tap(find.text(l.maintenanceTaskEnvironment));await tester.pumpAndSettle();
          expect(find.widgetWithText(SelectableText,scheduler==MachineTaskScheduler.cron?'259200':duration),findsOneWidget);
          expect(tester.takeException(),isNull);
          await tester.tap(close);await tester.pumpAndSettle();expect(find.byType(_MachineTaskDialog),findsNothing);
          await tester.pumpWidget(const SizedBox());
        }
      }
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('任务详情刷新保留内容和折叠状态，失败可恢复且不重复读取', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000,1000));
    final snapshot=MachineScheduledTaskSnapshot.parse(taskFixture());
    final task=MachineScheduledTask(scheduler:MachineTaskScheduler.systemd,id:'cleanup.timer',name:'cleanup.timer',source:'/etc/systemd/system/cleanup.timer',
      definition:'[Timer]\nOnCalendar=daily',command:'/usr/bin/cleanup',writable:true,metadata:const {'AccuracyUSec':'2000000'});
    var calls=0;Completer<String>? pending;
    await tester.pumpWidget(_SettingsApp(locale:const Locale('zh'),localizationsDelegates:AppLocalizations.localizationsDelegates,supportedLocales:AppLocalizations.supportedLocales,
      home:Scaffold(body:Builder(builder:(context)=>TextButton(onPressed:()=>showAnimatedDialog<void>(context:context,builder:(_)=>_MachineTaskDialog(platform:'Linux',
        snapshot:snapshot,task:task,edit:false,client:MachineScheduledTaskClient(platform:'Linux',run:(_)async {calls++;return pending==null?'__OH_TASK_END__':pending!.future;}))),child:const Text('打开详情'))))));
    await tester.tap(find.text('打开详情'));await tester.pumpAndSettle();
    final state=tester.state<_MachineTaskDialogState>(find.byType(_MachineTaskDialog));
    expect(find.text('删除'),findsNothing);expect(find.text('编辑'),findsOneWidget);
    await tester.ensureVisible(find.text('执行环境'));await tester.tap(find.text('执行环境'));await tester.pumpAndSettle();
    expect(find.text('2 秒'),findsOneWidget);
    pending=Completer<String>();final refresh=state._load();await tester.pump();
    final current=calls;await state._load();expect(calls,current);
    expect(find.byKey(const ValueKey('task-execution')),findsOneWidget);expect(find.text('2 秒'),findsOneWidget);
    pending!.completeError(const MachineTaskException('unavailable'));await refresh;pending=null;await tester.pumpAndSettle();
    expect(find.text('/usr/bin/cleanup'),findsOneWidget);expect(find.text('2 秒'),findsOneWidget);
    await state._load();await tester.pumpAndSettle();expect(state._error,isNull);expect(find.text('2 秒'),findsOneWidget);
    expect(tester.takeException(),isNull);await tester.pumpWidget(const SizedBox());await tester.binding.setSurfaceSize(null);
  });

  testWidgets('关闭任务详情后等待后台读取释放终端', (tester) async {
    final pending=Completer<String>(); bool Function()? cancelled; var busy=false; var calls=0;
    await tester.binding.setSurfaceSize(const Size(1100,900));
    await tester.pumpWidget(_SettingsApp(locale:const Locale('zh'),localizationsDelegates:AppLocalizations.localizationsDelegates,supportedLocales:AppLocalizations.supportedLocales,
      home:Scaffold(body:SingleChildScrollView(child:_MachineScheduledTaskPanel(platform:'Linux',refreshToken:0,onBusy:(value)=>busy=value,run:(command,check){
        if(calls++==0)return Future.value(taskFixture()); cancelled=check; return pending.future;
      })))));
    await tester.pumpAndSettle();
    final state=tester.state<_MachineScheduledTaskPanelState>(find.byType(_MachineScheduledTaskPanel));
    final opened=state._open(state._data!.tasks.first);
    await tester.pumpAndSettle(); expect(busy,isTrue); expect(cancelled!(),isFalse);
    Navigator.of(tester.element(find.byType(_MachineTaskDialog))).pop();
    await tester.pumpAndSettle(); expect(cancelled!(),isTrue); expect(busy,isTrue);
    pending.complete('__OH_TASK_END__'); await opened; await tester.pumpAndSettle();
    expect(busy,isFalse); expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox()); await tester.binding.setSurfaceSize(null);
  });
}
''';

const _incrementalChecks = r'''
String incrementalWire(Map<String, String> sections, {bool complete = false}) => '${sections.entries.map((e) => '__OH_OPS_${e.key}__\n${e.value}\n').join()}__OH_OPS_${complete ? 'end' : 'flush'}__\n';
Widget incrementalApp(_MaintenanceFixture service) => ChangeNotifierProvider<MachineTerminalFileService>.value(value: service,
  child: const _SettingsApp(locale: Locale('zh'), localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: _MachineMaintenanceDialog(sessionId: '会话', terminalId: '终端'))));
void incrementalChecks() {

  test('超时配置经过真实数据库编码、重开恢复及旧值兼容', () async {
    final directory = await Directory.systemTemp.createTemp('openhand-timeout-settings-');
    var database = await DatabaseService.initialize(databasePath: '${directory.path}/settings.db', useNoIsolateFactory: true);
    final store = SettingsStore();
    try {
      for (final seconds in machineMaintenanceTimeoutOptions) {
        await store.save(AppSettingsSnapshot.defaults().copyWith(maintenanceTimeoutSeconds: seconds));
        await database.close();
        database = await DatabaseService.initialize(databasePath: '${directory.path}/settings.db', useNoIsolateFactory: true);
        final loaded = await SettingsStore().load();
        expect(loaded.canPersist, isTrue);
        expect(loaded.snapshot.maintenanceTimeoutSeconds, seconds);
        expect(loaded.snapshot.copyWith(maintenanceWorkers: 8).maintenanceTimeoutSeconds, seconds);
      }
      final row = (await database.database.query('app_settings', where: 'key = ?', whereArgs: ['app_settings_json'])).single;
      final saved = jsonDecode(row['value'] as String) as Map<String, dynamic>;
      for (final invalid in [null, -1, 0, 31, 3601, 60.5, '损坏数据', true]) {
        final value = {...saved};
        if (invalid == null) { value.remove('maintenance_timeout_seconds'); }
        else { value['maintenance_timeout_seconds'] = invalid; }
        await database.database.update('app_settings', {'value': jsonEncode(value)}, where: 'key = ?', whereArgs: ['app_settings_json']);
        expect((await store.load()).snapshot.maintenanceTimeoutSeconds, 30);
      }
    } finally {
      await database.close(); await directory.delete(recursive: true);
    }
  });

  testWidgets('超时选择保存后重开弹窗和重建控制器保留，失败回滚且关闭期间保存安全', (tester) async {
    final store = _MemorySettingsStore();
    _testSettings.dispose(); _testSettings = await SettingsController.create(store: store);
    final service = _MaintenanceFixture();
    Future<void> open() async { await tester.pumpWidget(incrementalApp(service)); await tester.pumpAndSettle(); }
    _MaintenanceToolbarMenu<int> menu() => tester.widget<_MaintenanceToolbarMenu<int>>(find.byWidgetPredicate(
      (w) => w is _MaintenanceToolbarMenu<int> && w.icon == Icons.hourglass_bottom_rounded));
    Future<void> select(int value) async {
      await tester.runAsync(() async {
        menu().onSelected(value);
        await _testSettings.updateMaintenanceTimeoutSeconds(value);
      });
      await tester.pumpAndSettle();
    }
    await open(); expect(menu().value, 30);
    await select(900); expect(menu().value, 900);
    await tester.pumpWidget(const SizedBox()); await open();
    expect(menu().value, 900); expect(service.lastTimeout, const Duration(minutes: 15));
    await tester.pumpWidget(const SizedBox());
    _testSettings.dispose(); _testSettings = await SettingsController.create(store: store);
    await open(); expect(menu().value, 900); expect(service.lastTimeout, const Duration(minutes: 15));
    expect(await _testSettings.updateMaintenanceTimeoutSeconds(901), isFalse);
    store.fail = true;
    await select(3600); expect(menu().value, 900); expect(store.snapshot.maintenanceTimeoutSeconds, 900);
    expect(_testSettings.persistenceIssue?.kind, SettingsPersistenceIssueKind.saveFailed);
    store.fail = false;
    await tester.runAsync(() async { store.pending = Completer<void>(); menu().onSelected(60); });
    await tester.pump();
    expect(menu().enabled, isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async { store.pending!.complete(); await _testSettings.updateMaintenanceTimeoutSeconds(60); });
    store.pending = null;
    await open(); expect(menu().value, 60); expect(service.lastTimeout, const Duration(seconds: 60));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('超时菜单位于 Shell 与刷新间隔之间，六种语言与全部档位传递到采集链路', (tester) async {
    final service = _MaintenanceFixture();
    for (final locale in AppLocalizations.supportedLocales) {
      for (final width in [440.0, 1500.0]) {
        await tester.runAsync(() => _testSettings.updateMaintenanceTimeoutSeconds(30));
        await tester.binding.setSurfaceSize(Size(width, 1000));
        await tester.pumpWidget(ChangeNotifierProvider<MachineTerminalFileService>.value(value: service,
          child: _SettingsApp(locale: locale, localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => LayoutBuilder(builder: (context, constraints) => MediaQuery(
              data: MediaQuery.of(context).copyWith(size: constraints.biggest, textScaler: TextScaler.linear(width < 500 ? 1.4 : 1)), child: child!)),
            theme: ThemeData(fontFamily: Platform.environment['MAINTENANCE_FONT'] == null ? null : '运维预览字体'),
            home: const RepaintBoundary(key: ValueKey('超时菜单预览'), child: Scaffold(body: _MachineMaintenanceDialog(sessionId: '会话', terminalId: '终端'))))));
        await tester.pumpAndSettle();
        final state = tester.state<_MachineMaintenanceDialogState>(find.byType(_MachineMaintenanceDialog));
        final l = AppLocalizations.of(state.context)!;
        final selector = find.byWidgetPredicate((w) => w is _MaintenanceToolbarMenu<int> && w.tooltip == l.maintenanceTimeout);
        final shell = find.byType(_MaintenanceToolbarMenu<MachineTerminalCommandShell>);
        final interval = find.byWidgetPredicate((w) => w is _MaintenanceToolbarMenu<int> && w.icon == Icons.timer_outlined);
        expect(state._timeoutSeconds, 30);
        expect(tester.getTopLeft(shell).dx, lessThan(tester.getTopLeft(selector).dx));
        expect(tester.getTopLeft(selector).dx, lessThan(tester.getTopLeft(interval).dx));
        expect(tester.getSize(selector).height, tester.getSize(interval).height);
        for (final seconds in machineMaintenanceTimeoutOptions) {
          final menu = tester.widget<_MaintenanceToolbarMenu<int>>(selector);
          expect(menu.items.keys.toList(), machineMaintenanceTimeoutOptions);
          await tester.runAsync(() async {
            menu.onSelected(seconds);
            await _testSettings.updateMaintenanceTimeoutSeconds(seconds);
          });
          await tester.pumpAndSettle();
          await state._refresh(manual: true); await tester.pumpAndSettle();
          expect(service.lastTimeout, Duration(seconds: seconds));
          if (seconds == 30 && locale.toString() == 'zh' && width == 1500 && Platform.environment['MAINTENANCE_FONT'] != null) {
            await tester.runAsync(() async {
              final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('超时菜单预览')));
              final image = await boundary.toImage(); final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
              await File('/tmp/maintenance-timeout-menu.png').writeAsBytes(bytes!.buffer.asUint8List()); image.dispose();
            });
          }
          expect(service.lastCommand, contains('"\$oh_tick" -lt ${(seconds - 2) * 10}'));
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox());
      }
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('采集超时保留已有数据并显示本地化错误，手动重试可恢复且不打印预期堆栈', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    final service = _MaintenanceFixture();
    await tester.pumpWidget(incrementalApp(service)); await tester.pumpAndSettle();
    final state = tester.state<_MachineMaintenanceDialogState>(find.byType(_MachineMaintenanceDialog));
    final baseline = state._snapshots[0];
    final logs = <String>[];
    final previousPrint = debugPrint;
    try {
      debugPrint = (String? message, {int? wrapWidth}) { if (message != null) logs.add(message); };
      service.failure = TimeoutException('模拟终端超时');
      await state._refresh(manual: true); await tester.pumpAndSettle();
      expect(state._snapshots[0], same(baseline));
      expect(state._error, AppLocalizations.of(state.context)!.maintenanceCommandTimedOut);
      expect(state._loading, isFalse); expect(state._progressTimer, isNull);
      expect(logs.where((line) => line.contains('machine_maintenance')), isEmpty);
      service.failure = null;
      await state._refresh(manual: true); await tester.pumpAndSettle();
      expect(state._error, isNull); expect(state._snapshots[0]!.isComplete, isTrue);
      expect(tester.takeException(), isNull);
    } finally {
      debugPrint = previousPrint;
      await tester.pumpWidget(const SizedBox()); await tester.binding.setSurfaceSize(null);
    }
  });

  testWidgets('卡片有限高度与快速增量变更不溢出且内容仍可访问', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    for (final scale in [1.0, 2.0]) {
      for (final height in [109.0, 80.0]) {
        await tester.pumpWidget(_SettingsApp(locale: const Locale('zh'), localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, home: Scaffold(body: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Center(child: SizedBox(width: 568, height: height,
            child: _MaintenanceCard(title: '运行状态', scrollBody: false,
              child: Text('完整内容可访问', style: TextStyle(fontSize: 24, height: 1.6)))))))));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
        scroll.position.jumpTo(scroll.position.maxScrollExtent); await tester.pump();
        expect(find.text('完整内容可访问').hitTestable(), findsOneWidget);
      }
    }
    late StateSetter update;
    var populated = false;
    await tester.pumpWidget(_SettingsApp(locale: const Locale('zh'), localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, home: Scaffold(body: SingleChildScrollView(child: StatefulBuilder(
      builder: (context, setter) {
        update = setter;
        return _MaintenanceGrid(children: [
          _MaintenanceCard(title: '变化数据', child: populated
            ? const Text('内容变化\n多行数据\n完整显示')
            : const OpenHandOperationalEmptyState(message: '暂无可用数据')),
          const _MaintenanceCard(title: '运行状态', child: Text('正常')),
        ]);
      })))));
    await tester.pumpAndSettle();
    for (var i = 0; i < 6; i++) {
      update(() => populated = !populated); await tester.pump();
      for (var frame = 0; frame < 12; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.takeException(), isNull);
      }
    }
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox()); await tester.binding.setSurfaceSize(null);
  });

  testWidgets('运维空态六语言、主题和有限高度保持居中可读，悬停无阴影', (tester) async {
    for (final locale in AppLocalizations.supportedLocales) {
      for (final brightness in Brightness.values) {
        for (final size in [const Size(360, 240), const Size(760, 180), const Size(240, 80)]) {
          await tester.binding.setSurfaceSize(size);
          await tester.pumpWidget(_SettingsApp(locale:locale, localizationsDelegates:AppLocalizations.localizationsDelegates,
            supportedLocales:AppLocalizations.supportedLocales, theme:ThemeData(fontFamily:Platform.environment['MAINTENANCE_FONT'] == null ? null : '运维预览字体',colorScheme:ColorScheme.fromSeed(seedColor:const Color(0xff526914),brightness:brightness)),
            builder:(context, child) => MediaQuery(data:MediaQuery.of(context).copyWith(textScaler:const TextScaler.linear(1.8)), child:child!),
            home:const Scaffold(body:SizedBox.expand(child:OpenHandOperationalRankTable(headers:['指标'],rows:[])))));
          await tester.pumpAndSettle();
          final l = await AppLocalizations.delegate.load(locale);
          final message = find.text(l.maintenanceNoAvailableData);
          expect(message, findsOneWidget);
          final empty = find.byType(OpenHandOperationalEmptyState);
          final content = find.descendant(of:empty, matching:find.byType(Column)).first;
          expect(tester.getCenter(content).dx, closeTo(size.width / 2, .1));
          final icon = find.descendant(of:empty, matching:find.byType(Icon));
          expect(tester.getCenter(icon).dx, closeTo(tester.getCenter(message).dx, .1));
          if (size.height >= 180) expect(tester.getCenter(content).dy, closeTo(size.height / 2, .1));
          else {
            final scroll = tester.state<ScrollableState>(find.descendant(of:empty, matching:find.byType(Scrollable)).first);
            expect(scroll.position.maxScrollExtent, greaterThan(0));
            scroll.position.jumpTo(scroll.position.maxScrollExtent); await tester.pump();
            expect(tester.getRect(message).bottom, lessThanOrEqualTo(size.height));
          }
          final mouse = await tester.createGesture(kind:ui.PointerDeviceKind.mouse);
          await mouse.addPointer(location:Offset.zero); await mouse.moveTo(tester.getCenter(empty)); await tester.pumpAndSettle();
          for (final box in tester.widgetList<DecoratedBox>(find.descendant(of:empty,matching:find.byType(DecoratedBox)))) {
            if (box.decoration case final BoxDecoration decoration) {
              expect(decoration.gradient,isNull); expect(decoration.boxShadow ?? [],isEmpty);
            }
          }
          await mouse.removePointer(); expect(tester.takeException(),isNull);
          await tester.pumpWidget(const SizedBox());
        }
      }
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('实际趋势空态收拢留白，手动样本到达自然退场并遵循关闭动画设置', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000,800));
    final service = _MaintenanceFixture();
    await tester.pumpWidget(incrementalApp(service)); await tester.pumpAndSettle();
    final state = tester.state<_MachineMaintenanceDialogState>(find.byType(_MachineMaintenanceDialog));
    _MaintenanceCard trendCard() {
      final overview = state._overview(state._snapshots[0]!) as _MaintenanceAnimatedList;
      return overview.children.whereType<_MaintenanceGrid>().expand((grid) => grid.children).whereType<_MaintenanceCard>()
        .firstWhere((card) => card.title == 'CPU 实时趋势');
    }
    final card = trendCard();
    state._cpuHistory.addAll(const [(time:0,value:.2),(time:10,value:.4)]);
    final dataCard = trendCard();
    final frames = <bool>[false,true];
    for (final disabled in frames) {
      await tester.runAsync(() => _testSettings.updateDialogAnimationSettings(disabled
        ? const DialogAnimationSettings(entranceStyle:DialogAnimationStyle.none,exitStyle:DialogAnimationStyle.none)
        : const DialogAnimationSettings(durationMs:600,entranceStyle:DialogAnimationStyle.springScale,exitStyle:DialogAnimationStyle.fade)));
      for (final brightness in Brightness.values) {
        late StateSetter update;
        var populated = false;
        await tester.pumpWidget(_SettingsApp(locale:const Locale('zh'),localizationsDelegates:AppLocalizations.localizationsDelegates,
          supportedLocales:AppLocalizations.supportedLocales,theme:ThemeData(fontFamily:Platform.environment['MAINTENANCE_FONT'] == null ? null : '运维预览字体',colorScheme:ColorScheme.fromSeed(seedColor:const Color(0xff526914),brightness:brightness)),
          home:Scaffold(body:Center(child:RepaintBoundary(key:const ValueKey('空态预览'),child:SizedBox(width:380,
            child:StatefulBuilder(builder:(context,setter) { update=setter;
              return populated ? dataCard : card;
            })))))));
        await tester.pumpAndSettle();
        final emptyHeight = tester.getSize(find.byType(_MaintenanceCard)).height;
        expect(emptyHeight,lessThan(260));
        final message=find.text('等待更多采样以显示趋势');expect(message,findsOneWidget);
        final empty=find.byType(OpenHandOperationalEmptyState);
        expect(tester.getSize(empty).height,lessThan(90));
        expect(tester.getRect(message).right,lessThanOrEqualTo(tester.getRect(empty).right - 12));
        if (!disabled && Platform.environment['MAINTENANCE_FONT'] != null) {
          await tester.runAsync(() async {
            final boundary=tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('空态预览')));
            final image=await boundary.toImage(pixelRatio:2);final bytes=await image.toByteData(format:ui.ImageByteFormat.png);
            await File('/tmp/maintenance-empty-${brightness.name}.png').writeAsBytes(bytes!.buffer.asUint8List());image.dispose();
          });
        }
        update(() => populated=true); await tester.pump(); await tester.pump(const Duration(milliseconds:80));
        expect(message,disabled ? findsNothing : findsOneWidget);
        await tester.pumpAndSettle();expect(message,findsNothing);expect(find.byType(_MaintenanceTrend),findsOneWidget);
        expect(tester.getSize(find.byType(_MaintenanceCard)).height,greaterThan(emptyHeight));
        update(() => populated=false);await tester.pumpAndSettle();expect(message,findsOneWidget);
        expect(tester.takeException(),isNull);await tester.pumpWidget(const SizedBox());
      }
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('趋势与占比卡六语言明暗主题自适应，负载分栏、图例居中且悬停无阴影', (tester) async {
    for (final locale in AppLocalizations.supportedLocales) {
      final l = await AppLocalizations.delegate.load(locale);
      for (final brightness in Brightness.values) {
        final baseTheme = brightness == Brightness.light
            ? OpenHandTheme.light(OpenHandThemePreset.tundraGreen)
            : OpenHandTheme.dark(OpenHandThemePreset.tundraGreen);
        await tester.binding.setSurfaceSize(const Size(1000, 900));
        final service = _MaintenanceFixture();
        await tester.pumpWidget(ChangeNotifierProvider<MachineTerminalFileService>.value(value: service,
          child: _SettingsApp(theme: baseTheme, locale: locale, localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: _MachineMaintenanceDialog(sessionId: '会话', terminalId: '终端')))));
        await tester.pumpAndSettle();
        final state = tester.state<_MachineMaintenanceDialogState>(find.byType(_MachineMaintenanceDialog));
        final sample = MachineMaintenanceSnapshot({...state._snapshots[0]!.sections,
          'load': '3.02 3.23 3.31',
          'memory': ['MemTotal: 33554432 kB', 'MemAvailable: 9909043 kB'].join(String.fromCharCode(10)),
        });
        List<_MaintenanceCard> cards() => (state._overview(sample) as _MaintenanceAnimatedList).children
          .whereType<_MaintenanceGrid>().expand((grid) => grid.children).whereType<_MaintenanceCard>()
          .where((card) => card.title == l.maintenanceCpuTrend || card.title == l.maintenanceMemoryShare).toList();
        final empty = cards();
        state._cpuHistory.addAll(List.generate(12, (i) => (time: i * 10000.0, value: .2 + (i % 4) * .1)));
        final populated = cards();
        for (final size in [const Size(800, 700), const Size(320, 1600), const Size(240, 2000)]) {
          final scale = size.width == 800 ? 1.0 : 1.8;
          for (final data in [false, true]) {
            await tester.binding.setSurfaceSize(size);
            await tester.pumpWidget(_SettingsApp(locale: locale, localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: baseTheme.copyWith(textTheme: baseTheme.textTheme.apply(fontFamily: Platform.environment['MAINTENANCE_FONT'] == null ? null : '运维预览字体')),
              home: MediaQuery(data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
                child: Scaffold(body: SingleChildScrollView(child: RepaintBoundary(key: const ValueKey('图表卡片预览'),
                  child: Padding(padding: const EdgeInsets.all(12), child: _MaintenanceGrid(maxColumns: 2,
                    minWidth: 300, children: data ? populated : empty))))))));
            await tester.pumpAndSettle();
            for (final title in [l.maintenanceCpuTrend, l.maintenanceMemoryShare, l.maintenanceLoad,
                l.maintenanceReadoutTotal, l.maintenanceUsed, l.maintenanceAvailable,
                l.maintenanceLoadWindow('1'), l.maintenanceLoadWindow('5'), l.maintenanceLoadWindow('15')]) {
              expect(find.text(title), findsOneWidget, reason: locale.toString());
            }
            for (final value in ['3.02', '3.23', '3.31']) expect(find.text(value), findsOneWidget);
            final chart = find.byWidgetPredicate((w) => w is CustomPaint && w.painter is OpenHandDonutChartPainter);
            final painter = tester.widget<CustomPaint>(chart).painter as OpenHandDonutChartPainter;
            expect(painter.values.reduce((a,b) => a + b), 33554432 * 1024);
            final memory = find.byWidgetPredicate((w) => w is _MaintenanceCard && w.title == l.maintenanceMemoryShare);
            final content = find.descendant(of: memory, matching: find.byType(_MaintenanceVisual));
            final divider = find.descendant(of: memory, matching: find.byType(Divider));
            if (size.width == 800) {
              expect(tester.getCenter(content).dy, closeTo((tester.getRect(memory).bottom + tester.getRect(divider).bottom) / 2, 1));
              final windows = [for (final value in ['3.02', '3.23', '3.31']) tester.getRect(find.text(value))];
              expect(windows[1].top, windows.first.top); expect(windows[2].top, windows.first.top);
            } else {
              expect(tester.getRect(find.text(l.maintenanceUsed)).top, greaterThan(tester.getRect(chart).bottom));
              expect(tester.getRect(find.text('3.23')).top, greaterThan(tester.getRect(find.text('3.02')).bottom));
            }
            final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
            await mouse.addPointer(location: Offset.zero); await mouse.moveTo(tester.getCenter(memory)); await tester.pumpAndSettle();
            for (final box in tester.widgetList<DecoratedBox>(find.descendant(of: find.byKey(const ValueKey('图表卡片预览')), matching: find.byType(DecoratedBox)))) {
              if (box.decoration case final BoxDecoration decoration) {
                expect(decoration.gradient, isNull); expect(decoration.boxShadow ?? [], isEmpty);
              }
            }
            await mouse.removePointer();
            expect(tester.takeException(), isNull);
            if (Platform.environment['MAINTENANCE_PREVIEW'] != null &&
                (locale == const Locale('zh') || locale == const Locale('fr')) && size.width != 240) {
              await tester.runAsync(() async {
                final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('图表卡片预览')));
                final image = await boundary.toImage(pixelRatio: 2); final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
                await File('/tmp/maintenance-chart-' + locale.toString() + '-' + brightness.name + '-' + size.width.toInt().toString() + '-' + (data ? 'data' : 'empty') + '.png')
                  .writeAsBytes(bytes!.buffer.asUint8List()); image.dispose();
              });
            }
            await tester.pumpWidget(const SizedBox());
          }
        }
      }
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('列表增删平滑退场、重排保留数值模式，操作读取最新数据', (tester) async {
    await tester.runAsync(() => _testSettings.updateDialogAnimationSettings(const DialogAnimationSettings(durationMs: 600,
      entranceStyle: DialogAnimationStyle.springScale, exitStyle: DialogAnimationStyle.fade)));
    var revision = 1; var changed = false; int? selected; late StateSetter update;
    await tester.pumpWidget(_SettingsApp(locale: const Locale('zh'), localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales, home: Scaffold(body: StatefulBuilder(builder: (context, setter) {
        update = setter;
        return _MaintenanceTable(headers: const ['名称', '数值'], onRowTap: (row) => selected = row.data as int,
          rows: [for (final name in changed ? ['丙', '甲'] : ['甲', '乙']) OpenHandOperationalRankRow(
            rowKey: name, value: 0, data: revision, cells: [name, name == '甲' ? '1234567' : '5'],
            cellWidgets: [null, _MaintenanceNumber(raw: name == '甲' ? '1234567' : '5')])]);
      }))));
    await tester.pumpAndSettle();
    final value = find.byWidgetPredicate((w) => w is _MaintenanceNumber && w.raw == '1234567');
    final state = tester.state<_MaintenanceNumberState>(value);
    await tester.tap(value); await tester.pumpAndSettle(); expect(state._exact, isTrue);
    update(() { changed = true; revision = 2; }); await tester.pump(); await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('乙'), findsOneWidget); expect(find.text('乙').hitTestable(), findsNothing);
    await tester.pumpAndSettle(); expect(find.text('乙'), findsNothing);
    expect(identical(tester.state(value), state), isTrue); expect(state._exact, isTrue);
    tester.widget<OpenHandOperationalRowMenu>(find.byType(OpenHandOperationalRowMenu).last).onDetails!();
    expect(selected, 2); expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('分块刷新即时更新快卡、保留慢卡和缓存，完成提交且失败恢复', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    final service = _MaintenanceFixture();
    await tester.pumpWidget(incrementalApp(service)); await tester.pumpAndSettle();
    final state = tester.state<_MachineMaintenanceDialogState>(find.byType(_MachineMaintenanceDialog));
    final baseline = state._snapshots[0]!;
    final cachedProcesses = baseline.processes;
    final next = {...baseline.sections, 'uptime': '1020', 'memory': 'MemTotal: 8388608 kB\nMemAvailable: 2097152 kB'};
    service.pending = Completer<String>();
    final refresh = state._refresh(); await tester.pump();
    final prefix = incrementalWire({for (final key in ['platform','host','boot','uptime']) key: next[key]!});
    service.outputCallback!(prefix + incrementalWire({'memory': next['memory']!}));
    await tester.pump(const Duration(milliseconds: 50)); await tester.pump();
    final partial = state._snapshots[0]!;
    expect(partial.isComplete, isFalse);
    expect(partial.memory['MemAvailable'], 2097152 * 1024);
    expect(partial.text('network'), baseline.text('network'));
    expect(identical(partial.processes, cachedProcesses), isTrue);
    expect(state._loading, isTrue);
    final body = state._body;
    service.outputCallback!(prefix + incrementalWire({'memory': next['memory']!}));
    await tester.pump(const Duration(milliseconds: 50));
    expect(identical(body, state._body), isTrue, reason: '重复输出不应触发重建');
    service.pending!.complete(incrementalWire(next, complete: true));
    await refresh; await tester.pumpAndSettle();
    final committed = state._snapshots[0]!;
    expect(committed.isComplete, isTrue); expect(state._loading, isFalse);
    final history = List.of(state._cpuHistory);
    service.pending = Completer<String>();
    final failed = state._refresh(); await tester.pump();
    service.outputCallback!(prefix + incrementalWire({'memory': 'MemTotal: 8388608 kB\nMemAvailable: 1024 kB'}));
    await tester.pump(const Duration(milliseconds: 50));
    expect(state._snapshots[0]!.memory['MemAvailable'], 1024 * 1024);
    service.pending!.completeError(StateError('模拟末段失败'));
    await failed; await tester.pumpAndSettle();
    expect(identical(state._snapshots[0], committed), isTrue);
    expect(state._cpuHistory, history); expect(state._progressTimer, isNull);
    expect(state._error, '模拟末段失败');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox()); await tester.binding.setSurfaceSize(null);
  });

  testWidgets('局部数据到达期间不抢占定时任务通道，完整提交只触发一次采集', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1100));
    final service = _MaintenanceFixture();
    await tester.pumpWidget(incrementalApp(service)); await tester.pumpAndSettle();
    final state = tester.state<_MachineMaintenanceDialogState>(find.byType(_MachineMaintenanceDialog));
    final sections = state._snapshots[0]!.sections;
    service.pending = Completer<String>();
    await tester.tap(find.text('系统服务')); await tester.pump();
    final wire = incrementalWire(sections);
    service.outputCallback!(wire);
    await tester.pump(const Duration(milliseconds: 50)); await tester.pumpAndSettle();
    final taskFinder = find.byType(_MachineScheduledTaskPanel);
    await tester.scrollUntilVisible(taskFinder, 400, scrollable: find.descendant(of: find.byType(CustomScrollView).first, matching: find.byType(Scrollable)).first);
    await tester.pumpAndSettle();
    expect(service.taskCalls, 0); expect(state._scheduledTasksBusy, isFalse);
    service.outputCallback!(wire + incrementalWire({'manager': sections['manager']!}));
    await tester.pump(const Duration(milliseconds: 50));
    expect(service.taskCalls, 0);
    service.pending!.complete(incrementalWire(sections, complete: true)); service.pending = null;
    await tester.pumpAndSettle();
    expect(service.taskCalls, 1); expect(state._scheduledTasksBusy, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox()); await tester.binding.setSurfaceSize(null);
  });

  testWidgets('分块更新切换和关闭后不发布迟到内容，回滚未完成日志', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    final service = _MaintenanceFixture();
    await tester.pumpWidget(incrementalApp(service)); await tester.pumpAndSettle();
    final state = tester.state<_MachineMaintenanceDialogState>(find.byType(_MachineMaintenanceDialog));
    await tester.tap(find.text('日志管理')); await tester.pumpAndSettle();
    final baseline = state._snapshots[5]!;
    final count = state._logBuffers['system']?.entries.length ?? 0;
    service.pending = Completer<String>();
    final refreshing = state._refresh(); await tester.pump();
    final wire = incrementalWire({for (final key in ['platform','host','boot','uptime']) key: baseline.text(key), 'log_system': '新增日志样本'});
    service.outputCallback!(wire); await tester.pump(const Duration(milliseconds: 50));
    expect(state._logBuffers['system']!.entries.length, greaterThan(count));
    await tester.tap(find.text('运行总览')); await tester.pump();
    service.outputCallback!(wire + incrementalWire({'log_kernel': '迟到内核日志'}));
    await tester.pump(const Duration(milliseconds: 50));
    expect(state._logBuffers['kernel']?.entries.any((e) => e.message.contains('迟到内核日志')) ?? false, isFalse);
    service.pending!.completeError(StateError('模拟切换后失败')); service.pending = null;
    await refreshing; await tester.pumpAndSettle();
    expect(state._logBuffers['system']?.entries.length ?? 0, count);
    expect(identical(state._snapshots[5], baseline), isTrue);
    service.pending = Completer<String>(); final closing = state._refresh(); await tester.pump();
    final callback = service.outputCallback!;
    await tester.pumpWidget(const SizedBox());
    callback(wire); service.pending!.complete(incrementalWire(baseline.sections, complete: true));
    await closing; await tester.pump(const Duration(seconds: 1));
    expect(state._progressTimer?.isActive ?? false, isFalse);
    expect(tester.takeException(), isNull); await tester.binding.setSurfaceSize(null);
  });

  testWidgets('数据过渡只重建变化值，快速往返限制退场层并遵循全局动画', (tester) async {
    await tester.runAsync(() => _testSettings.updateDialogAnimationSettings(const DialogAnimationSettings(durationMs: 600,
      entranceStyle: DialogAnimationStyle.fade, exitStyle: DialogAnimationStyle.fade)));
    var value = '甲'; var builds = 0; var reduced = false; late StateSetter update;
    await tester.pumpWidget(_SettingsApp(home: Scaffold(body: StatefulBuilder(builder: (context, setter) {
      update = setter;
      final current = value;
      return MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: reduced), child: OpenHandOperationalLiveContent(
        value: current, builder: () => Builder(builder: (_) { builds++; return Text(current); })));
    }))));
    await tester.pumpAndSettle(); final first = builds;
    update(() {}); await tester.pumpAndSettle(); expect(builds, first);
    update(() => value = '乙'); await tester.pump(); await tester.pump(const Duration(milliseconds: 80));
    expect(builds, first + 1); expect(find.text('甲'), findsOneWidget); expect(find.text('乙'), findsOneWidget);
    update(() => value = '甲'); await tester.pump();
    update(() => value = '丙'); await tester.pump();
    expect(find.byType(Text), findsNWidgets(2)); expect(tester.takeException(), isNull);
    await tester.pumpAndSettle(); expect(find.text('丙'), findsOneWidget);
    update(() { reduced = true; value = '丁'; }); await tester.pump(); await tester.pump();
    expect(find.text('丙'), findsNothing); expect(find.text('丁'), findsOneWidget);
    await tester.runAsync(() => _testSettings.updateDialogAnimationSettings(const DialogAnimationSettings(entranceStyle: DialogAnimationStyle.none, exitStyle: DialogAnimationStyle.none)));
    update(() { reduced = false; value = '戊'; }); await tester.pump(); await tester.pump();
    expect(find.text('丁'), findsNothing); expect(find.text('戊'), findsOneWidget);
    expect(tester.takeException(), isNull); await tester.pumpWidget(const SizedBox());
  });

  testWidgets('集群版本和节点独立更新，失败保留旧字段且不递归嵌套', (tester) async {
    Completer<String>? version, nodes;
    var invalidVersion = false;
    Future<String> run(String command) async {
      if (!command.startsWith("'kubectl'")) throw StateError('模拟运行时不可用');
      if (command.contains("'current-context'")) return '测试集群';
      if (command.contains("'get' 'pods'")) return '{"items":[]}';
      if (command.contains("'version'")) return invalidVersion ? '{' : version?.future ?? '{"serverVersion":{"gitVersion":"v1"}}';
      if (command.contains("'get' 'nodes'")) return nodes?.future ?? '{"items":[{"metadata":{"name":"节点一"}}]}';
      return '';
    }
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    await tester.pumpWidget(_SettingsApp(locale: const Locale('zh'), localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales, home: Scaffold(body: _MachineContainerPanel(
        sessionId:'会话', terminalId:'终端', run:run, windows:false, shell:MachineTerminalCommandShell.posix))));
    await selectContainerList(tester);
    await tester.pumpAndSettle();
    final state = tester.state<_MachineContainerPanelState>(find.byType(_MachineContainerPanel));
    final original = jsonDecode(state._metadata) as Map;
    version = Completer<String>(); nodes = Completer<String>();
    final refresh = state.refresh(); await tester.pump();
    expect(jsonDecode(state._metadata), original);
    version.complete('{"serverVersion":{"gitVersion":"v2"}}'); await tester.pump(); await tester.pump(const Duration(milliseconds: 700));
    final partial = jsonDecode(state._metadata) as Map;
    expect(partial['版本'], {'serverVersion': {'gitVersion':'v2'}});
    expect(partial['节点'], original['节点']); expect(state._busy, isTrue);
    nodes.complete('{"items":[{"metadata":{"name":"节点二"}}]}');
    await refresh; await tester.pumpAndSettle();
    invalidVersion = true; nodes = null;
    await state.refresh(); await tester.pumpAndSettle();
    final recovered = jsonDecode(state._metadata) as Map;
    expect(recovered['版本'], partial['版本']); expect(recovered['节点'], original['节点']);
    expect(state._collectionIssues, contains('运行时元数据与状态'));
    expect((recovered['版本'] as Map).containsKey('节点'), isFalse);
    invalidVersion = false; version = Completer<String>(); nodes = Completer<String>();
    state._scope.text = '新范围'; final changed = state.refresh(applyScope:true); await tester.pump();
    expect(state._metadata, isEmpty); expect(state._kubernetesMetadata, isEmpty);
    version.complete('{"serverVersion":{"gitVersion":"v3"}}'); await tester.pump(); await tester.pump(const Duration(milliseconds: 700));
    expect((jsonDecode(state._metadata) as Map).containsKey('节点'), isFalse);
    nodes.complete('{"items":[]}'); await changed; await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox()); await tester.binding.setSurfaceSize(null);
  });

  testWidgets('CRI 刷新保留待更新 Pod，失败保留旧列表且切换范围清空旧记录', (tester) async {
    Completer<String>? pods;
    var revision = 1, fail = false;
    Future<String> run(String command) async {
      if (!command.startsWith("'crictl'")) throw StateError('模拟运行时不可用');
      if (command.contains("'ps'")) return '{"containers":[{"id":"c$revision","metadata":{"name":"容器$revision"},"state":"CONTAINER_RUNNING"}]}';
      if (command.contains("'pods'")) {
        if (fail) throw StateError('模拟 Pod 采集失败');
        return pods?.future ?? '{"items":[{"id":"p1","metadata":{"name":"Pod 一"},"state":"SANDBOX_READY"}]}';
      }
      return '{}';
    }
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    await tester.pumpWidget(_SettingsApp(locale: const Locale('zh'), localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales, home: Scaffold(body: _MachineContainerPanel(
        sessionId:'会话', terminalId:'终端', run:run, windows:false, shell:MachineTerminalCommandShell.posix))));
    await selectContainerList(tester);
    await tester.pumpAndSettle();
    final state = tester.state<_MachineContainerPanelState>(find.byType(_MachineContainerPanel));
    final previous = state._entries.singleWhere((entry) => entry.isPod);
    revision = 2; pods = Completer<String>(); final refresh = state.refresh(); await tester.pump(); await tester.pump(const Duration(milliseconds: 700));
    expect(state._entries.singleWhere((entry) => !entry.isPod).id, 'c2');
    expect(state._entries.singleWhere((entry) => entry.isPod), same(previous)); expect(state._busy, isTrue);
    pods.complete('{"items":[{"id":"p2","metadata":{"name":"Pod 二"},"state":"SANDBOX_READY"}]}');
    await refresh; await tester.pumpAndSettle();
    fail = true; revision = 3; await state.refresh(); await tester.pumpAndSettle();
    expect(state._entries.map((entry) => entry.id), ['c3','p2']);
    expect(state._collectionIssues['Pod 列表'], contains('模拟 Pod 采集失败'));
    fail = false; pods = Completer<String>(); state._scope.text = 'unix:///测试.sock';
    final changed = state.refresh(applyScope:true); await tester.pump(); await tester.pump(const Duration(milliseconds: 700));
    expect(state._entries.where((entry) => entry.isPod), isEmpty);
    pods.complete('{"items":[]}'); await changed; await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox()); await tester.binding.setSurfaceSize(null);
  });

  testWidgets('容器元数据在指标完成前可见，指标失败保留上次有效值', (tester) async {
    final metadata = Completer<String>(), metrics = Completer<String>();
    var delay = true, fail = false;
    Future<String> run(String command) async {
      if (command.contains("'context' 'show'")) return 'default';
      if (command.contains("'ps'")) return '{"ID":"abc","Names":"服务","State":"running"}';
      if (command.contains("'info'")) return delay ? metadata.future : '{"ServerVersion":"28.0"}';
      if (command.contains("'stats'")) { if (fail) throw StateError('模拟指标不可用'); return delay ? metrics.future : '{}'; }
      return '{}';
    }
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    await tester.pumpWidget(_SettingsApp(locale: const Locale('zh'), localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales, home: Scaffold(body: _MachineContainerPanel(
        sessionId:'会话', terminalId:'终端', run:run, windows:false, shell:MachineTerminalCommandShell.posix))));
    await selectContainerList(tester);
    await tester.pump(); await tester.pump(const Duration(milliseconds: 700)); final state = tester.state<_MachineContainerPanelState>(find.byType(_MachineContainerPanel));
    expect(state._entries.single.name, '服务'); expect(state._busy, isTrue);
    metadata.complete('{"ServerVersion":"27.0"}'); await tester.pump(); await tester.pump(const Duration(milliseconds: 700));
    expect(state._metadata, contains('27.0')); expect(state._busy, isTrue);
    metrics.complete('{"Name":"服务","CPUPerc":"4%"}'); await tester.pumpAndSettle();
    expect(state._busy, isFalse); final previous = state._metrics;
    delay = false; fail = true; await state.refresh(); await tester.pumpAndSettle();
    expect(state._metadata, contains('28.0')); expect(state._metrics, previous);
    expect(state._collectionIssues['实时资源采样'], contains('模拟指标不可用'));
    expect(tester.takeException(), isNull); await tester.pumpWidget(const SizedBox()); await tester.binding.setSurfaceSize(null);
  });
}
''';

const _containerTerminalChecks = r'''
class _ContainerTerminalSession extends Fake implements MachineTerminalSession {
  @override
  final String id = '容器测试终端';
  @override
  final terminal = Terminal(maxLines: 1000)..resize(80, 24);
}
class _ContainerTerminalFixture extends Fake with ChangeNotifier implements MachineTerminalService {
  final session = _ContainerTerminalSession();
  final pending = Completer<MachineTerminalCommandResult>();
  MachineTerminalCommandOutputCallback? output;
  MachineTerminalUploadCancelCheck? cancelled;
  final writes = <String>[];
  final sizes = <(int, int)>[];
  bool missing = false, exitOnEof = true;
  bool? startsOnExecute, startsOnInput;
  Duration? timeout;
  int commands = 0;

  Future<void> initialize() async {
    session.terminal.write('\x1b[32m/data # \x1b[0m');
  }
  @override
  MachineTerminalSession? terminalFor(String sessionId, String terminalId) => missing ? null : session;
  @override
  Future<MachineTerminalCommandResult> executeCommand({required String sessionId, required String command,
    String? terminalId, Duration timeout = kMachineTerminalDefaultCommandTimeout, bool startIfNeeded = true,
    bool recordHistory = true, bool displayOutput = true, MachineTerminalCommandShell commandShell = MachineTerminalCommandShell.automatic,
    MachineTerminalCommandOutputCallback? onOutput, MachineTerminalUploadCancelCheck? isCancelled}) {
    commands++; startsOnExecute = startIfNeeded; this.timeout = timeout;
    output = onOutput; cancelled = isCancelled;
    return pending.future;
  }
  @override
  Future<void> writeInput({required String sessionId, required String data, String? terminalId,
    bool appendNewline = false, bool startIfNeeded = true}) async {
    startsOnInput = startIfNeeded; writes.add(data);
    if (data == '\x04' && exitOnEof) finish();
  }
  @override
  Future<void> resizeTerminal({required String sessionId, String? terminalId, required int columns, required int rows}) async {
    sizes.add((columns, rows));
  }
  void finish({bool failed = false}) {
    if (pending.isCompleted) return;
    pending.complete(MachineTerminalCommandResult(terminalId: session.id, command: '容器命令', output: '',
      status: MachineTerminalStatus.running, durationMs: 1, exitCode: failed ? 1 : 0, error: failed ? '模拟连接失败' : null));
  }
  Future<void> release() async {
    finish();
    dispose();
  }
}

Widget containerTerminalScreen(_ContainerTerminalFixture service, {Locale locale = const Locale('zh'),
  Brightness brightness = Brightness.light, double scale = 1, GlobalKey? preview}) =>
  ChangeNotifierProvider<MachineTerminalService>.value(value: service,
    child: _SettingsApp(locale: locale, localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(brightness: brightness, colorSchemeSeed: const Color(0xff647332),
        fontFamily: Platform.environment['MAINTENANCE_FONT'] == null ? null : '运维预览字体'),
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
      home: Scaffold(body: Builder(builder: (context) => TextButton(
        onPressed: () => showAnimatedDialog<void>(context: context, barrierDismissible: false, dismissOnEscape: false,
          builder: (_) => RepaintBoundary(key: preview, child: _ContainerInteractiveTerminal(
            title: 'openhand-redis · 缓存服务', sessionId: '会话', terminalId: service.session.id,
            command: '容器命令', readyMarker: '__TEST_CONTAINER_READY__', shell: MachineTerminalCommandShell.posix))), child: const Text('打开容器终端'))))));

void containerTerminalChecks() {
  testWidgets('容器终端六语言明暗主题、窄窗大字号统一工具栏且状态切换保留画布', (tester) async {
    for (final locale in AppLocalizations.supportedLocales) {
      for (final brightness in Brightness.values) {
        for (final size in [const Size(1200, 900), const Size(420, 480)]) {
          final fixture = _ContainerTerminalFixture();
          await tester.runAsync(fixture.initialize);
          final initialSize = (fixture.session.terminal.viewWidth, fixture.session.terminal.viewHeight);
          final preview = GlobalKey();
          final scale = size.width < 500 ? 1.6 : 1.0;
          final l = await AppLocalizations.delegate.load(locale);
          await tester.binding.setSurfaceSize(size);
          await tester.pumpWidget(containerTerminalScreen(fixture, locale: locale, brightness: brightness, scale: scale, preview: preview));
          await tester.tap(find.text('打开容器终端')); await tester.pump(); await tester.pump(const Duration(milliseconds: 800)); await tester.pumpAndSettle();
          expect(tester.widget<TerminalView>(find.byType(TerminalView)).readOnly, isTrue);
          fixture.output!('宿主回显'); await tester.pump();
          expect(tester.widget<TerminalView>(find.byType(TerminalView)).readOnly, isTrue);
          final canvas = tester.state(find.byType(_MachineTerminalViewport));
          fixture.output!('__TEST_CONTAINER_READY__'); await tester.pumpAndSettle();
          expect(find.text(l.maintenanceMetricConnected), findsOneWidget);
          expect(find.text(l.maintenanceContainerTerminal), findsOneWidget);
          expect(find.textContaining('输入 exit'), findsNothing);
          expect(tester.widget<TerminalView>(find.byType(TerminalView)).readOnly, isFalse);
          expect(identical(canvas, tester.state(find.byType(_MachineTerminalViewport))), isTrue);
          final buttons = find.descendant(of: find.byType(_ContainerInteractiveTerminal), matching: find.byType(OutlinedButton));
          expect(buttons, findsNWidgets(2));
          expect(tester.getSize(buttons.first).height, _maintenanceControlHeight);
          expect(tester.getSize(buttons.last), tester.getSize(buttons.first));
          for (final box in tester.widgetList<DecoratedBox>(find.descendant(of: find.byType(_ContainerInteractiveTerminal), matching: find.byType(DecoratedBox)))) {
            if (box.decoration is BoxDecoration) {
              final decoration = box.decoration as BoxDecoration;
              expect(decoration.gradient, isNull); expect(decoration.boxShadow ?? [], isEmpty);
            }
          }
          if (Platform.environment['MAINTENANCE_PREVIEW'] != null && locale == const Locale('zh')) {
            await tester.runAsync(() async {
              final image = await (preview.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage(pixelRatio: 1.5);
              final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
              await File('/tmp/container-terminal-${brightness.name}-${size.width.toInt()}.png').writeAsBytes(bytes!.buffer.asUint8List()); image.dispose();
            });
          }
          await tester.tap(find.byTooltip('${l.maintenanceContainerInterrupt} (Ctrl+C)')); await tester.pump();
          expect(fixture.writes, ['\x03']); expect(fixture.startsOnInput, isFalse);
          await tester.tap(find.byTooltip('${l.maintenanceContainerExit} (Ctrl+D)')); await tester.pumpAndSettle();
          expect(fixture.writes, ['\x03', '\x04']);
          expect(find.descendant(of: find.byType(_MaintenanceStatus), matching: find.text(l.maintenanceExited)), findsOneWidget);
          expect(tester.widget<TerminalView>(find.byType(TerminalView)).readOnly, isTrue);
          expect(identical(canvas, tester.state(find.byType(_MachineTerminalViewport))), isTrue);
          expect(fixture.startsOnExecute, isFalse); expect(fixture.timeout, const Duration(minutes: 10));
          await tester.tap(find.byTooltip(openHandCloseLabel(tester.element(find.byType(_ContainerInteractiveTerminal)))));
          await tester.pumpAndSettle(); expect(find.byType(_ContainerInteractiveTerminal), findsNothing);
          expect(fixture.sizes, [initialSize]); expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox()); await tester.runAsync(fixture.release);
        }
      }
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('连接中可取消，原终端缺失不持续加载，强制离开清理采集回调', (tester) async {
    for (final mode in ['连接中', '缺失', '移除']) {
      final fixture = _ContainerTerminalFixture(); await tester.runAsync(fixture.initialize);
      fixture.missing = mode == '缺失';
      await tester.binding.setSurfaceSize(const Size(800, 620));
      await tester.pumpWidget(containerTerminalScreen(fixture));
      await tester.tap(find.text('打开容器终端')); await tester.pump(); await tester.pump(const Duration(milliseconds: 800)); await tester.pumpAndSettle();
      if (mode == '缺失') {
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.text('原终端已关闭，请重新连接。'), findsWidgets);
        expect(fixture.commands, 0);
      } else if (mode == '移除') {
        await tester.pumpWidget(const SizedBox());
        expect(fixture.cancelled!(), isTrue);
        fixture.output!('迟到的输出'); fixture.finish(failed: true);
        await tester.pump(); expect(tester.takeException(), isNull);
        await tester.runAsync(fixture.release); continue;
      }
      await tester.tap(find.byTooltip('关闭')); await tester.pump();
      if (mode == '连接中') {
        expect(fixture.cancelled!(), isTrue); expect(fixture.writes, isEmpty);
        fixture.pending.completeError(const MachineTerminalUploadCancelled());
      }
      await tester.pumpAndSettle();
      expect(find.byType(_ContainerInteractiveTerminal), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox()); await tester.runAsync(fixture.release);
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('前台程序忽略退出时保留交互，不重复发送 EOF 或提前关闭', (tester) async {
    final fixture = _ContainerTerminalFixture(); await tester.runAsync(fixture.initialize);
    fixture.exitOnEof = false;
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    await tester.pumpWidget(containerTerminalScreen(fixture));
    await tester.tap(find.text('打开容器终端')); await tester.pump(); await tester.pump(const Duration(milliseconds: 800)); await tester.pumpAndSettle();
    fixture.output!('__TEST_CONTAINER_READY__'); await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('关闭')); await tester.pump();
    await tester.tap(find.byTooltip('关闭')); await tester.pump();
    expect(fixture.writes, ['\x04']); expect(fixture.cancelled!(), isFalse);
    expect(tester.widget<TerminalView>(find.byType(TerminalView)).readOnly, isTrue);
    await tester.pump(const Duration(seconds: 4)); await tester.pumpAndSettle();
    expect(find.text('当前程序尚未退出。请先中断程序，再退出终端。'), findsOneWidget);
    expect(tester.widget<TerminalView>(find.byType(TerminalView)).readOnly, isFalse);
    await tester.tap(find.byTooltip('中断 (Ctrl+C)')); await tester.pump();
    fixture.exitOnEof = true;
    await tester.tap(find.byTooltip('关闭')); await tester.pumpAndSettle();
    expect(fixture.writes, ['\x04', '\x03', '\x04']);
    expect(find.byType(_ContainerInteractiveTerminal), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox()); await tester.runAsync(fixture.release);
    await tester.binding.setSurfaceSize(null);
  });
}
''';

const _telemetryChecks = r'''
Future<void> selectContainerList(WidgetTester tester) async {
  final panel = find.byType(_MachineContainerPanel);
  final tab = find.widgetWithText(ChoiceChip, maintenanceLabel(tester.element(panel), '容器'));
  await tester.ensureVisible(tab);
  await tester.tap(tab);
}

String telemetryFixture(String command) {
  if (command.contains("'current-context'")) return '测试集群';
  if (command.contains("'context' 'show'")) return 'desktop-linux';
  if (command.contains("'ps'")) return '';
  if (command.contains("'--raw=/readyz'")) return 'ok';
  if (command.contains("'info'")) return '{"Name":"运维引擎","ServerVersion":"28.0.1","NCPU":8,"MemTotal":17179869184,"ContainersRunning":3,"Images":8,"Driver":"overlay2","CgroupDriver":"systemd","LoggingDriver":"json-file","LiveRestoreEnabled":true}';
  if (command.contains("'version'")) return '{"serverVersion":{"gitVersion":"v1.33.0"},"clientVersion":{"gitVersion":"v1.33.1"}}';
  if (command.contains("'stats'")) return '{"Name":"api","Container":"container-123","CPUPerc":"12.5%","MemUsage":"256MiB / 2GiB","NetIO":"12MB / 4MB","BlockIO":"8MB / 1MB","PIDs":"18"}';
  if (command.contains("'system' 'df'")) return '{"Type":"Images","TotalCount":"8","Active":"3","Size":"2.4GB","Reclaimable":"1.2GB"}';
  if (command.contains("'network' 'ls'")) return '{"Name":"bridge","Driver":"bridge","Scope":"local"}';
  if (command.contains("'top' 'nodes'")) return 'NAME    CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%\nnode-1  500m         6%     2048Mi          12%';
  if (command.contains("'top' 'pods'")) return 'NAMESPACE   POD       NAME   CPU(cores)   MEMORY(bytes)\n生产        api-pod   api    100m         256Mi';
  if (command.contains("'get' 'nodes'")) return jsonEncode({'items':[{'metadata':{'name':'node-1'},'status':{'capacity':{'cpu':'8','memory':'16Gi'},'allocatable':{'cpu':'7500m','memory':'15Gi','pods':'110'},'conditions':[{'type':'Ready','status':'True'}],'nodeInfo':{'containerRuntimeVersion':'containerd://2.0','osImage':'Ubuntu 24.04','kernelVersion':'6.8','architecture':'arm64'},'addresses':[{'type':'InternalIP','address':'10.0.0.2'}]}}]});
  if (command.contains("'get' 'events'")) return jsonEncode({'items':[{'metadata':{'namespace':'生产'},'involvedObject':{'name':'api-pod'},'type':'Warning','reason':'BackOff','message':'测试告警','count':3,'lastTimestamp':'2026-10-02T09:00:00Z'}]});
  if (command.contains("'get' 'deployments,statefulsets,daemonsets,jobs,cronjobs'")) return jsonEncode({'items':[{'kind':'Deployment','metadata':{'name':'api','namespace':'生产'},'spec':{'replicas':3},'status':{'readyReplicas':2,'availableReplicas':2}}]});
  return '{"items":[]}';
}

void telemetryChecks() {
  for (final locale in AppLocalizations.supportedLocales) {
    for (final width in [380.0, 1180.0]) {
      for (final brightness in Brightness.values) {
        testWidgets('遥测分区国际化与布局 ' + locale.toString() + ' ' + width.toString() + ' ' + brightness.name, (tester) async {
          await tester.binding.setSurfaceSize(Size(width, 1050));
          final l = await AppLocalizations.delegate.load(locale);
          final key = GlobalKey<_ContainerTelemetryPanelState>();
          _ContainerQueryScope? scope;
          final client = MachineContainerClient(runtime:MachineContainerRuntime.docker,contextName:'desktop-linux',run:(command)async=>telemetryFixture(command));
          _ContainerQueryScope begin() {
            scope?.cancel();
            return scope = _ContainerQueryScope(fallback:client.run,timeout:machineContainerTelemetryTimeout,previous:scope?.settled);
          }
          Future<void> screen(bool kube) async {
            final theme = brightness == Brightness.light ? OpenHandTheme.light(OpenHandThemePreset.tundraGreen) : OpenHandTheme.dark(OpenHandThemePreset.tundraGreen);
            await tester.pumpWidget(_SettingsApp(locale:locale,localizationsDelegates:AppLocalizations.localizationsDelegates,supportedLocales:AppLocalizations.supportedLocales,
              theme:theme.copyWith(textTheme:theme.textTheme.apply(fontFamily:Platform.environment['MAINTENANCE_FONT'] == null ? null : '运维预览字体')),
              builder:(context,child)=>MediaQuery(data:MediaQuery.of(context).copyWith(textScaler:TextScaler.linear(width < 500 ? 1.6 : 1)),child:child!),
              home:Scaffold(body:RepaintBoundary(key:const ValueKey('遥测预览'),child:SingleChildScrollView(padding:const EdgeInsets.all(16),child:_ContainerTelemetryPanel(key:key,client:client,kubernetes:kube,windows:false,beginQuery:begin))))));
            await tester.pumpAndSettle();
          }
          for (final kube in [false,true]) {
            await screen(kube);
            final state = key.currentState!;
            expect(state._busy,isFalse); expect(state._issues,isEmpty); expect(state._error,isEmpty);
            expect(state._reports.length,kube ? 13 : 5);
            expect(find.text(kube ? l.maintenanceTelemetryKubernetesOverview : l.maintenanceTelemetryRuntimeOverview),findsWidgets);
            expect(find.text(kube ? l.maintenanceTelemetryApiHealth : l.maintenanceContainerMetadata),findsWidgets);
            expect(find.text(kube ? l.maintenanceTelemetryNodeMetrics : l.maintenanceContainerMetrics),findsWidgets);
            expect(find.text('采样时间'),findsNothing);
            expect(maintenanceDetailLabel(state.context, 'Container'), l.maintenanceContainerList);
            if (l.maintenanceContainerList != 'Container') expect(find.text('Container'), findsNothing);
            final section = find.byKey(ValueKey(kube ? 'telemetry-readiness' : 'telemetry-metadata'));
            final metadata = find.descendant(of: section, matching: find.widgetWithText(FilledButton, l.maintenanceTelemetryFullMetadata));
            expect(metadata, findsOneWidget);
            final content = tester.widget<_MaintenanceSection>(section).child as Column;
            expect(tester.getTopLeft(metadata).dy - tester.getBottomLeft(find.byWidget(content.children[content.children.length - 2])).dy,
              greaterThanOrEqualTo(_maintenanceGridGap));
            final button = tester.widget<FilledButton>(metadata);
            final colors = Theme.of(tester.element(metadata)).colorScheme;
            expect(button.style!.backgroundColor!.resolve({}), colors.surface.withValues(alpha:.72));
            expect((button.style!.shape!.resolve({}) as RoundedRectangleBorder).borderRadius, kOpenHandBorderRadius8);
            expect(button.style!.elevation!.resolve({WidgetState.hovered}), 0);
            expect(tester.takeException(),isNull);
            for (final decorated in tester.widgetList<DecoratedBox>(find.byType(DecoratedBox))) {
              if (decorated.decoration case final BoxDecoration decoration) {
                expect(decoration.gradient,isNull); expect(decoration.boxShadow ?? [],isEmpty);
              }
            }
            if (Platform.environment['MAINTENANCE_PREVIEW'] != null && locale == const Locale('zh')) {
              await tester.runAsync(() async {
                final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('遥测预览')));
                final shot = await boundary.toImage(pixelRatio:1.5); final data = await shot.toByteData(format:ui.ImageByteFormat.png);
                await File('/tmp/container-telemetry-' + (kube ? 'kube' : 'runtime') + '-' + brightness.name + '-' + width.toInt().toString() + '.png').writeAsBytes(data!.buffer.asUint8List()); shot.dispose();
              });
            }
          }
          await tester.pumpWidget(const SizedBox()); await tester.binding.setSurfaceSize(null);
        });
      }
    }
  }

  testWidgets('默认概览先识别运行时，可取消并重试且不重复采集指标', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1180, 1000));
    Completer<String>? discovery = Completer<String>();
    bool Function()? cancelled;
    final calls = <String>[];
    Future<String> run(String command, {required Duration timeout, void Function(String)? onOutput, bool Function()? isCancelled}) async {
      calls.add(command);
      if (discovery != null && command.contains("'ps'")) { cancelled = isCancelled; return discovery!.future; }
      return telemetryFixture(command);
    }
    await tester.pumpWidget(_SettingsApp(locale: const Locale('zh'), localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales, home: Scaffold(body: _MachineContainerPanel(
        sessionId:'会话', terminalId:'终端', run:(command)=>run(command, timeout: const Duration(seconds:30)), query:run,
        windows:false, shell:MachineTerminalCommandShell.posix))));
    await tester.pump(); await tester.pump(const Duration(milliseconds: 700));
    final panel = tester.state<_MachineContainerPanelState>(find.byType(_MachineContainerPanel));
    expect(panel._resourceTab, 3); expect(panel._client, isNull); expect(panel._busy, isTrue);
    expect(calls.where((command)=>command.contains("'info'")), isEmpty);
    final cancel = find.byKey(const ValueKey('telemetry-cancel'));
    await tester.ensureVisible(cancel); await tester.tap(cancel); await tester.pumpAndSettle();
    expect(cancelled!(), isTrue); expect(panel._busy, isFalse);
    expect(find.text('采集已取消'), findsWidgets);
    discovery!.complete('{"ID":"迟到容器","Names":"迟到容器"}'); discovery=null; await tester.pumpAndSettle();
    expect(panel._client, isNull); expect(panel._entries, isEmpty);
    await tester.tap(find.byKey(const ValueKey('telemetry-refresh'))); await tester.pumpAndSettle();
    expect(panel._client, isNotNull); expect(panel._telemetryKey.currentState!._reports.length, 5);
    expect(calls.where((command)=>command.contains("'info'")), hasLength(1));
    expect(calls.where((command)=>command.contains("'stats'")), hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox()); await tester.binding.setSurfaceSize(null);
  });
  testWidgets('集群概览六语言明暗窄屏统一控件，诊断可展开且取消后不接收迟到结果', (tester) async {
    for (final locale in AppLocalizations.supportedLocales) {
      final l = await AppLocalizations.delegate.load(locale);
      for (final width in [380.0, 1180.0]) {
        await tester.binding.setSurfaceSize(Size(width, 1050));
        var failed = true;
        Completer<String>? pending;
        Future<String> run(String command) async {
          if (command.contains("'current-context'")) {
            if (failed) throw StateError('permission denied');
            if (pending != null) return pending!.future;
          }
          return telemetryFixture(command);
        }
        final theme = width < 500 ? OpenHandTheme.dark(OpenHandThemePreset.tundraGreen) : OpenHandTheme.light(OpenHandThemePreset.tundraGreen);
        final key = GlobalKey<_ContainerTelemetryPanelState>();
        await tester.pumpWidget(_SettingsApp(locale:locale, localizationsDelegates:AppLocalizations.localizationsDelegates,
          supportedLocales:AppLocalizations.supportedLocales,
          theme:theme.copyWith(textTheme:theme.textTheme.apply(fontFamily:Platform.environment['MAINTENANCE_FONT'] == null ? null : '运维预览字体')),
          builder:(context,child)=>MediaQuery(data:MediaQuery.of(context).copyWith(textScaler:TextScaler.linear(width < 500 ? 1.6 : 1)),child:child!),
          home:Scaffold(body:RepaintBoundary(key:const ValueKey('遥测状态预览'), child:SingleChildScrollView(padding:const EdgeInsets.all(16),
            child:_ContainerTelemetryPanel(key:key, client:MachineContainerClient(runtime:MachineContainerRuntime.docker, contextName:'Docker 上下文', run:run), kubernetes:true, windows:false,
              beginQuery:()=>_ContainerQueryScope(fallback:run, timeout:machineContainerTelemetryTimeout)))))));
        await tester.pumpAndSettle();
        expect(find.text(l.maintenanceTelemetryKubernetesOverview), findsOneWidget);
        expect(find.text('Docker 上下文'), findsNothing);
        expect(find.text(l.maintenanceContainerPermissionTitle), findsOneWidget);
        expect(find.text('Bad state: permission denied'), findsNothing);
        final refresh = find.byKey(const ValueKey('telemetry-refresh'));
        expect(tester.getSize(refresh).height, tester.getSize(find.byType(TextField)).height);
        Future<void> preview(String phase) async {
          if (Platform.environment['MAINTENANCE_PREVIEW'] == null || locale != const Locale('zh')) return;
          await tester.runAsync(() async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('遥测状态预览')));
            final image = await boundary.toImage(pixelRatio:1.5); final data = await image.toByteData(format:ui.ImageByteFormat.png);
            await File('/tmp/container-telemetry-' + phase + '-' + width.toInt().toString() + '.png').writeAsBytes(data!.buffer.asUint8List()); image.dispose();
          });
        }
        await preview('error');
        final diagnostics = find.text(l.maintenanceDiagnosticItems);
        await tester.ensureVisible(diagnostics); await tester.tap(diagnostics); await tester.pumpAndSettle();
        expect(find.text('Bad state: permission denied'), findsOneWidget);
        failed=false; pending=Completer<String>();
        await tester.ensureVisible(refresh); await tester.tap(refresh); await tester.pump(); await tester.pump(const Duration(milliseconds:700));
        expect(tester.widget<FilledButton>(refresh).onPressed, isNull);
        final cancel = find.byKey(const ValueKey('telemetry-cancel'));
        expect(tester.getSize(cancel).height, tester.getSize(refresh).height);
        await preview('loading');
        await tester.ensureVisible(cancel); await tester.tap(cancel); await tester.pumpAndSettle();
        expect(key.currentState!._cancelled, isTrue);
        pending!.complete('迟到上下文'); pending=null; await tester.pumpAndSettle();
        expect(key.currentState!._reports, isEmpty); expect(find.text('迟到上下文'), findsNothing);
        await tester.ensureVisible(refresh); await tester.tap(refresh); await tester.pumpAndSettle();
        expect(key.currentState!._reports.length, 13); expect(key.currentState!._completed, 13);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('遥测失败保留旧值并逐项重试', (tester) async {
    var failed=false; final commands=<String>[];
    Future<String> run(String command) async {
      commands.add(command);
      if(failed && command.contains("'top' 'nodes'")) throw StateError('error: Metrics API not available');
      return telemetryFixture(command);
    }
    _ContainerQueryScope? query;
    final key=GlobalKey<_ContainerTelemetryPanelState>();
    await tester.pumpWidget(_SettingsApp(locale:const Locale('zh'),localizationsDelegates:AppLocalizations.localizationsDelegates,supportedLocales:AppLocalizations.supportedLocales,
      home:Scaffold(body:SingleChildScrollView(child:_ContainerTelemetryPanel(key:key,client:MachineContainerClient(runtime:MachineContainerRuntime.kubernetes,contextName:'测试集群',run:run),kubernetes:true,windows:false,
        beginQuery:()=>query=_ContainerQueryScope(fallback:run,timeout:machineContainerTelemetryTimeout,previous:query?.settled))))));
    await tester.pumpAndSettle(); final state=key.currentState!; final previous=state._reports['node_metrics']; final stamp=state._updated['node_metrics'];
    failed=true; await state.refresh(); await tester.pumpAndSettle();
    expect(state._reports['node_metrics'],same(previous));expect(state._updated['node_metrics'],stamp);
    expect(state._issues.keys,['node_metrics']);expect(state._reports.containsKey('events'),isTrue);
    expect(find.textContaining('刷新失败，当前显示上次成功结果'),findsWidgets);
    final retry = find.descendant(of: find.byKey(const ValueKey('telemetry-node_metrics')),
      matching: find.widgetWithText(FilledButton, AppLocalizations.of(state.context)!.maintenanceImageTagRetry));
    expect(retry, findsOneWidget);
    await tester.ensureVisible(retry); await tester.pumpAndSettle();
    failed=false;commands.clear();await tester.tap(retry);await tester.pumpAndSettle();
    expect(state._issues,isEmpty);expect(commands.length,1);expect(commands.single,contains("'top' 'nodes'"));
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Kubernetes 缺少独立客户端时仅尝试一次 k3s，不掩盖连接错误', (tester) async {
    for (final missing in [true,false]) {
      final calls=<String>[];
      Future<String> run(String command) async {
        calls.add(command);
        if (command.startsWith("'kubectl'")) throw StateError(missing ? 'kubectl: command not found' : '连接上下文无效');
        return telemetryFixture(command);
      }
      final key=GlobalKey<_ContainerTelemetryPanelState>();
      await tester.pumpWidget(_SettingsApp(locale:const Locale('zh'),localizationsDelegates:AppLocalizations.localizationsDelegates,supportedLocales:AppLocalizations.supportedLocales,
        home:Scaffold(body:SingleChildScrollView(child:_ContainerTelemetryPanel(key:key,client:null,kubernetes:true,windows:false,
          beginQuery:()=>_ContainerQueryScope(fallback:run,timeout:machineContainerTelemetryTimeout))))));
      await tester.pumpAndSettle();
      expect(calls.where((command)=>command.startsWith("'kubectl'")),hasLength(1));
      if(missing) {
        expect(key.currentState!._client!.launcher,['k3s','kubectl']);expect(key.currentState!._reports.length,13);
      } else {
        expect(calls,hasLength(1));expect(key.currentState!._error,isNotEmpty);
        final readout = find.byWidgetPredicate((widget) => widget is _ContainerTelemetryIssue && widget.text == key.currentState!._error);
        final refresh = find.byKey(const ValueKey('telemetry-refresh'));
        expect(tester.getTopLeft(readout).dy - tester.getBottomLeft(refresh).dy, greaterThanOrEqualTo(_maintenanceGridGap));
      }
      await tester.pumpWidget(const SizedBox());
    }
  });
  testWidgets('切换命名空间取消旧采样并清空跨作用域缓存，遵守全局超时', (tester) async {
    final pending=Completer<String>();var delayed=false;final durations=<Duration>[];final calls=<String>[];
    Future<String> runner(String command,{required Duration timeout,void Function(String)? onOutput,bool Function()? isCancelled}) async {
      durations.add(timeout);calls.add(command);
      if(delayed && command.contains("'get' 'nodes'")) return pending.future;
      return telemetryFixture(command);
    }
    final key=GlobalKey<_ContainerTelemetryPanelState>();_ContainerQueryScope? scope;
    await tester.pumpWidget(_SettingsApp(locale:const Locale('zh'),localizationsDelegates:AppLocalizations.localizationsDelegates,supportedLocales:AppLocalizations.supportedLocales,
      home:Scaffold(body:SingleChildScrollView(child:_ContainerTelemetryPanel(key:key,client:MachineContainerClient(runtime:MachineContainerRuntime.kubernetes,contextName:'测试集群',run:(command)async=>telemetryFixture(command)),kubernetes:true,windows:false,
        beginQuery:(){scope?.cancel();return scope=_ContainerQueryScope(fallback:(command)async=>telemetryFixture(command),query:runner,timeout:const Duration(seconds:5),previous:scope?.settled);})))));
    await tester.pumpAndSettle();final state=key.currentState!;delayed=true;
    final old=state.refresh();await tester.pump();expect(state._active,'nodes');final oldScope=scope!;
    state._namespace.text='新命名空间';final changed=state.refresh(replace:true);await tester.pump();expect(oldScope.cancelled,isTrue);expect(state._reports,isEmpty);
    delayed=false;pending.complete('{"items":[{"metadata":{"name":"迟到节点"}}]}');await old;await changed;await tester.pumpAndSettle();
    expect(state._client!.scope,'新命名空间');expect(state._reports['nodes']!.rows.first.first,'node-1');expect(state._issues,isEmpty);
    expect(durations.every((duration)=>duration<=const Duration(seconds:5)),isTrue);
    expect(calls.last,contains("'-n' '新命名空间'"));expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('遥测切换与取消丢弃迟到结果，镜像列表仍可操作', (tester) async {
    final pending=Completer<String>(); var delay=false;
    Future<String> run(String command) async {
      if(delay && command.contains("'info'")) return pending.future;
      if(command.contains("'image' 'ls'")) return '[]';
      return telemetryFixture(command);
    }
    await tester.binding.setSurfaceSize(const Size(1180,900));
    await tester.pumpWidget(_SettingsApp(locale:const Locale('zh'),localizationsDelegates:AppLocalizations.localizationsDelegates,supportedLocales:AppLocalizations.supportedLocales,
      home:Scaffold(body:_MachineContainerPanel(sessionId:'会话',terminalId:'终端',run:run,windows:false,shell:MachineTerminalCommandShell.posix))));
    await tester.pumpAndSettle(); final parent=tester.state<_MachineContainerPanelState>(find.byType(_MachineContainerPanel));
    expect(parent._resourceTab,3);
    final tabs = tester.widgetList<ChoiceChip>(find.byType(ChoiceChip)).toList();
    expect(tabs.first.selected,isTrue);
    expect(find.descendant(of:find.byWidget(tabs.first),matching:find.text('运行时概览')),findsOneWidget);
    expect(find.descendant(of:find.byWidget(tabs[1]),matching:find.text('容器')),findsOneWidget);
    delay=true;parent.refresh();await tester.pump();await tester.pump(const Duration(milliseconds:700));
    final state=parent._telemetryKey.currentState!;expect(state._busy,isTrue);
    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip,'镜像')).onSelected,isNotNull);
    await tester.tap(find.widgetWithText(ChoiceChip,'镜像'));await tester.pump();
    expect(state._query!.cancelled,isTrue);
    pending.complete('{"Name":"迟到引擎"}');await tester.pumpAndSettle();
    expect(parent._resourceTab,1);expect(find.text('迟到引擎'),findsNothing);expect(parent._overlay,isFalse);
    expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox());await tester.binding.setSurfaceSize(null);
  });
}
''';

const _resourceChecks = r'''
void resourceChecks() {
  testWidgets('可编辑候选遵循菜单进退场、减少动画和禁用状态', (tester) async {
    final controller = TextEditingController();
    for (final reduced in [false, true]) {
      await tester.runAsync(() => _testSettings.updateMenuAnimationSettings(
        reduced ? OpenHandMotionDefaults.disabled : const DialogAnimationSettings(durationMs: 300,
          entranceStyle: DialogAnimationStyle.fadeScale, exitStyle: DialogAnimationStyle.fadeScale)));
      var enabled = true;
      late StateSetter update;
      await tester.pumpWidget(_SettingsApp(home: Scaffold(body: StatefulBuilder(builder: (context, setState) {
        update = setState;
        return SizedBox(width: 320, child: AnimatedEditableDropdown(
          controller: controller, enabled: enabled,
          decoration: const InputDecoration(),
          entries: const [DropdownMenuEntry(value: '1', label: '候选一'), DropdownMenuEntry(value: '2', label: '候选二')],
        ));
      }))));
      await tester.tap(find.byType(TextField)); await tester.pumpAndSettle();
      expect(find.text('候选一'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape); await tester.pump();
      if (!reduced) expect(find.text('候选一'), findsOneWidget);
      await tester.pumpAndSettle(); expect(find.text('候选一'), findsNothing);
      await tester.tap(find.byType(TextField)); await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape); await tester.pump(const Duration(milliseconds: 40));
      await tester.tap(find.byType(TextField)); await tester.pumpAndSettle();
      expect(find.text('候选一'), findsOneWidget);
      update(() => enabled = false); await tester.pumpAndSettle();
      expect(find.text('候选一'), findsNothing);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
    controller.dispose();
  });

  testWidgets('镜像候选六语言宽窄屏可选择本地引用并保持手动输入', (tester) async {
    for (final locale in AppLocalizations.supportedLocales) {
      final l = await AppLocalizations.delegate.load(locale);
      for (final width in [1180.0, 420.0]) {
        await tester.binding.setSurfaceSize(Size(width, 1000));
        final calls = <String>[];
        final theme = width < 500 ? OpenHandTheme.dark(OpenHandThemePreset.tundraGreen) : OpenHandTheme.light(OpenHandThemePreset.tundraGreen);
        await tester.pumpWidget(_SettingsApp(
          locale: locale, theme: theme.copyWith(textTheme: theme.textTheme.apply(fontFamily: Platform.environment['MAINTENANCE_FONT'] == null ? null : '运维预览字体')),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => RepaintBoundary(key: const ValueKey('镜像候选预览'), child: MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(width < 500 ? 1.5 : 1)), child: child!)),
          home: Scaffold(body: _ContainerResourceFormDialog(
            client: MachineContainerClient(runtime: MachineContainerRuntime.docker, run: (command) async { calls.add(command); return 'created'; }),
            action: _ContainerResourceAction.createContainer, timeout: const Duration(seconds: 30),
            imageReferences: const ['nginx:alpine', 'redis:7'],
            registryFactory: () => MachineImageRegistry(read: (_) async => {'results': []}),
          ))));
        await tester.pumpAndSettle();
        final form = tester.state<_ContainerResourceFormDialogState>(find.byType(_ContainerResourceFormDialog));
        final input = find.byWidgetPredicate((widget) => widget is TextField && widget.controller == form._controller('image'));
        final dropdown = find.ancestor(of: input, matching: find.byType(AnimatedEditableDropdown));
        await tester.tap(find.descendant(of: dropdown, matching: find.byType(IconButton)));
        await tester.pumpAndSettle();
        final option = find.widgetWithText(InkWell, 'redis:7');
        expect(option, findsOneWidget);
        if (Platform.environment['MAINTENANCE_PREVIEW'] != null && locale == const Locale('zh')) {
          await tester.runAsync(() async {
            final image = await tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('镜像候选预览'))).toImage(pixelRatio: 1.5);
            final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
            await File('/tmp/container-image-candidates-${width.toInt()}.png').writeAsBytes(bytes!.buffer.asUint8List()); image.dispose();
          });
        }
        await tester.tap(option); await tester.pumpAndSettle();
        expect(form._value('image'), 'redis:7');
        expect(calls, isEmpty);
        await tester.enterText(input, 'registry.local:5000/team/app:v2');
        await tester.pumpAndSettle();
        expect(form._value('image'), 'registry.local:5000/team/app:v2');
        final section = find.byWidgetPredicate((widget) => widget is _MaintenanceSection && widget.title == maintenanceLabel(form.context, '端口'));
        await tester.ensureVisible(section);
        await tester.tap(find.descendant(of: section, matching: find.byType(ListTile)).first);
        await tester.pumpAndSettle();
        final add = find.descendant(of: section, matching: find.widgetWithText(FilledButton, l.maintenanceResourceAddRow));
        await tester.ensureVisible(add); await tester.pumpAndSettle();
        final button = tester.widget<FilledButton>(add);
        expect(button.style!.backgroundColor!.resolve({}), theme.colorScheme.surface.withValues(alpha:.72));
        await tester.tap(add); await tester.pumpAndSettle();
        expect(form._ports.length, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('镜像候选异步标签立即更新且迟到、失败与关闭不覆盖输入', (tester) async {
    final requests = <Uri>[];
    final pending = <String, Completer<Map<String, dynamic>>>{};
    final controller = TextEditingController();
    var failed = false;
    final registry = MachineImageRegistry(read: (uri) async {
      requests.add(uri);
      if (failed) throw const FormatException('模拟仓库不可用');
      if (uri.path.endsWith('/tags')) {
        return pending.putIfAbsent(uri.path, Completer<Map<String, dynamic>>.new).future;
      }
      return {'results': [{'repo_name': uri.queryParameters['query']}]};
    });
    await tester.pumpWidget(_SettingsApp(locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SizedBox(width: 320, child: _ContainerImageReferenceField(
        controller: controller, enabled: true, style: null, references: const [],
        decoration: const InputDecoration(hintText: '镜像引用'),
        registryFactory: () => registry,
      )))));
    final input = find.byType(TextField);
    await tester.enterText(input, 'nginx:al'); await tester.pump(const Duration(milliseconds: 301));
    expect(requests.single.queryParameters['name'], 'al');
    await tester.enterText(input, 'redis:7'); await tester.pump(const Duration(milliseconds: 301));
    pending['/v2/namespaces/library/repositories/redis/tags']!.complete({'results': [{'name': '7.4'}, {'name': '7.2'}], 'next': null});
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InkWell, 'redis:7.4'), findsOneWidget);
    pending['/v2/namespaces/library/repositories/nginx/tags']!.complete({'results': [{'name': 'alpine'}], 'next': null});
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InkWell, 'nginx:alpine'), findsNothing);
    final loaded = requests.length;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown); await tester.pumpAndSettle();
    expect(controller.text, 'redis:7');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown); await tester.pumpAndSettle();
    expect(controller.text, 'redis:7');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter); await tester.pumpAndSettle();
    expect(controller.text, 'redis:7.2');
    expect(requests.length, loaded);
    failed = true;
    await tester.enterText(input, 'nginx:custom'); await tester.pump(const Duration(milliseconds: 301)); await tester.pumpAndSettle();
    expect(controller.text, 'nginx:custom');
    expect(find.textContaining('手动'), findsOneWidget);
    final count = requests.length;
    await tester.enterText(input, 'registry.local:5000/app:v1'); await tester.pumpAndSettle();
    expect(requests.length, count);
    failed = false;
    await tester.enterText(input, 'ubuntu:24'); await tester.pump(const Duration(milliseconds: 301));
    await tester.pumpWidget(const SizedBox());
    pending['/v2/namespaces/library/repositories/ubuntu/tags']!.complete({'results': [{'name': '24.04'}], 'next': null});
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    controller.dispose();
  });

  testWidgets('全局开关跨平台遵循主题并支持键盘、语义和禁用状态', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      for (final platform in TargetPlatform.values) {
        for (final brightness in Brightness.values) {
          final theme = (brightness == Brightness.dark
              ? OpenHandTheme.dark(OpenHandThemePreset.tundraGreen)
              : OpenHandTheme.light(OpenHandThemePreset.tundraGreen)).copyWith(platform: platform);
          var value = false;
          var enabled = true;
          var changes = 0;
          late StateSetter update;
          await tester.pumpWidget(MaterialApp(theme: theme, home: Scaffold(
            body: StatefulBuilder(builder: (context, setState) {
              update = setState;
              return SwitchListTile(title: const Text('开关'), value: value,
                onChanged: enabled ? (next) => setState(() { value = next; changes++; }) : null);
            }))));
          await tester.pumpAndSettle();
          expect(find.byType(CupertinoSwitch), findsNothing);
          final toggle = find.byType(Switch);
          final icon = Theme.of(tester.element(toggle)).switchTheme.thumbIcon!;
          expect(icon.resolve({})!.icon, Icons.close_rounded);
          expect(icon.resolve({WidgetState.selected})!.icon, Icons.check_rounded);
          expect(icon.resolve({WidgetState.disabled})!.icon, Icons.lock_outline_rounded);
          expect(icon.resolve({WidgetState.disabled, WidgetState.selected})!.icon, Icons.lock_outline_rounded);
          expect(tester.getSemantics(toggle), matchesSemantics(label: '开关',
            hasEnabledState: true, isEnabled: true, hasToggledState: true, hasSelectedState: true,
            isToggled: false, isFocusable: true, hasTapAction: true, hasFocusAction: true));
          final size = tester.getSize(toggle);
          await tester.tap(toggle); await tester.pumpAndSettle();
          expect(value, isTrue); expect(changes, 1);
          expect(tester.getSize(toggle), size);
          await tester.sendKeyEvent(LogicalKeyboardKey.tab); await tester.pumpAndSettle();
          await tester.sendKeyEvent(LogicalKeyboardKey.space); await tester.pumpAndSettle();
          expect(value, isFalse); expect(changes, 2);
          update(() => enabled = false); await tester.pumpAndSettle();
          await tester.tap(toggle); await tester.pumpAndSettle();
          expect(changes, 2);
          expect(tester.widget<Switch>(toggle).onChanged, isNull);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        }
      }
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('镜像搜索六语言支持标签选择、计数切换、仅拉取与创建容器', (tester) async {
    for (final locale in AppLocalizations.supportedLocales) {
      final l = await AppLocalizations.delegate.load(locale);
      for (final width in [1180.0, 420.0]) {
        await tester.binding.setSurfaceSize(Size(width, 960));
        final stats = Completer<Map<String, dynamic>>();
        final commands = <String>[];
        var created = 0;
        MachineImageRegistry registryFactory() => MachineImageRegistry(read: (uri) async {
          if (uri.path.endsWith('/tags')) return {'results': [{'name': 'latest'}, {'name': 'stable'}, {'name': '1.28-alpine'}], 'next': null};
          if (uri.path.contains('/catalog/')) return {'results': [{'slug': 'nginx', 'logo_url': {'small': 'https://example.invalid/nginx.png'}}]};
          return stats.future;
        });
        final client = MachineContainerClient(runtime: MachineContainerRuntime.docker, contextName: 'desktop-linux', run: (command) async {
          commands.add(command);
          if (command.contains("'search'")) return '{"Name":"nginx","Description":"Web server","StarCount":21396,"IsOfficial":"*"}';
          return 'container-created';
        });
        final theme = width < 500 ? OpenHandTheme.dark(OpenHandThemePreset.tundraGreen) : OpenHandTheme.light(OpenHandThemePreset.tundraGreen);
        await tester.pumpWidget(_SettingsApp(locale: locale, localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales,
          theme: theme.copyWith(textTheme: theme.textTheme.apply(fontFamily: Platform.environment['MAINTENANCE_FONT'] == null ? null : '运维预览字体')),
          builder: (context, child) => RepaintBoundary(key: const ValueKey('镜像搜索预览'), child: MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(width < 500 ? 1.5 : 1)), child: child!)),
          home: Scaffold(body: _ContainerRegistryDialog(client: client, registryFactory: registryFactory, timeout: const Duration(seconds: 30), onCreated: () => created++))));
        await tester.pumpAndSettle();
        final registry = tester.state<_ContainerRegistryDialogState>(find.byType(_ContainerRegistryDialog));
        registry._query.text = 'nginx'; await registry._search(); await tester.pumpAndSettle();
        expect(registry._busy, isFalse); expect(registry._results.single.official, isTrue);
        final selecting = registry._selectTag(registry._results.single); await tester.pumpAndSettle();
        expect(find.text(l.maintenanceImageSelectTag), findsOneWidget);
        await tester.ensureVisible(find.widgetWithText(ListTile, '1.28-alpine')); await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ListTile, '1.28-alpine')); await tester.pumpAndSettle();
        if (Platform.environment['MAINTENANCE_PREVIEW'] != null && locale == const Locale('zh')) {
          await tester.runAsync(() async {
            final image = await tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('镜像搜索预览'))).toImage(pixelRatio: 1.5);
            final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
            await File('/tmp/registry-tags-${width.toInt()}.png').writeAsBytes(bytes!.buffer.asUint8List()); image.dispose();
          });
        }
        await tester.tap(find.text(l.commonConfirm)); await tester.pumpAndSettle(); await selecting;
        expect(registry._tags['nginx'], '1.28-alpine');
        stats.complete({'results': [{'repo_name': 'nginx', 'star_count': 21396, 'pull_count': 13413760258, 'is_official': true}]}); await tester.pumpAndSettle();
        expect(registry._results.single.pulls, 13413760258); expect(registry._tags['nginx'], '1.28-alpine');
        for (final metric in [('stars', 21396), ('pulls', 13413760258)]) {
          final number = find.byKey(ValueKey(('nginx', metric.$1)));
          if (locale.scriptCode == 'Hant') expect(tester.widget<_MaintenanceNumber>(number).readable, contains(metric.$1 == 'stars' ? '萬' : '億'));
          await tester.ensureVisible(number); await tester.pumpAndSettle();
          await tester.tap(number); await tester.pumpAndSettle();
          expect(tester.state<_MaintenanceNumberState>(number)._exact, isTrue);
          expect(find.descendant(of: number, matching: find.text('${metric.$2}')), findsOneWidget);
          await tester.tap(number); await tester.pumpAndSettle();
          expect(tester.state<_MaintenanceNumberState>(number)._exact, isFalse);
        }
        if (Platform.environment['MAINTENANCE_PREVIEW'] != null && locale == const Locale('zh')) {
          await tester.runAsync(() async {
            final image = await tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('镜像搜索预览'))).toImage(pixelRatio: 1.5);
            final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
            await File('/tmp/registry-results-${width.toInt()}.png').writeAsBytes(bytes!.buffer.asUint8List()); image.dispose();
          });
        }
        var table = tester.widget<_MaintenanceTable>(find.byType(_MaintenanceTable));
        expect(table.headers, contains(l.maintenanceImageDownloads));
        final actions = table.rowActions!(table.rows.single);
        expect(actions.keys, [l.maintenanceImageSelectTag, l.maintenanceImagePullOnly, l.maintenanceContainerCreate]);
        actions[l.maintenanceImagePullOnly]!(); await tester.pumpAndSettle();
        var form = tester.state<_ContainerResourceFormDialogState>(find.byType(_ContainerResourceFormDialog));
        expect(form._value('image'), 'nginx:1.28-alpine');
        await form._submit(); await tester.pumpAndSettle();
        expect(commands.last, contains("'--context' 'desktop-linux' 'pull' 'nginx:1.28-alpine'"));
        expect(commands.any((command) => command.contains("'run'")), isFalse);
        await tester.ensureVisible(find.text(l.maintenanceResourceCloseRefresh)); await tester.tap(find.text(l.maintenanceResourceCloseRefresh)); await tester.pumpAndSettle();
        table = tester.widget<_MaintenanceTable>(find.byType(_MaintenanceTable));
        table.rowActions!(table.rows.single)[l.maintenanceContainerCreate]!(); await tester.pumpAndSettle();
        form = tester.state<_ContainerResourceFormDialogState>(find.byType(_ContainerResourceFormDialog));
        expect(form._value('image'), 'nginx:1.28-alpine');
        await form._submit(); await tester.pumpAndSettle();
        expect(commands.last, contains("'--context' 'desktop-linux' 'run'")); expect(commands.last, contains("'nginx:1.28-alpine'"));
        await tester.ensureVisible(find.text(l.maintenanceResourceCloseRefresh)); await tester.tap(find.text(l.maintenanceResourceCloseRefresh)); await tester.pumpAndSettle();
        expect(created, 1); expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('镜像元数据迟到不覆盖新搜索，标签失败可手动输入且关闭不写回', (tester) async {
    final pending = <Completer<Map<String, dynamic>>>[];
    var fail = false;
    MachineImageRegistry factory() => MachineImageRegistry(read: (uri) async {
      if (uri.path.contains('/catalog/')) return {'results': []};
      if (uri.path.endsWith('/tags') || fail) throw const FormatException('模拟仓库不可用');
      final request = Completer<Map<String, dynamic>>(); pending.add(request); return request.future;
    });
    final client = MachineContainerClient(runtime: MachineContainerRuntime.docker, run: (_) async => '{"Name":"nginx","StarCount":1}');
    await tester.pumpWidget(_SettingsApp(locale: const Locale('zh'), localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: _ContainerRegistryDialog(client: client, registryFactory: factory, timeout: const Duration(seconds: 30)))));
    await tester.pumpAndSettle();
    final registry = tester.state<_ContainerRegistryDialogState>(find.byType(_ContainerRegistryDialog));
    registry._query.text = 'nginx'; await registry._search(); await registry._search();
    pending[1].complete({'results': [{'repo_name': 'nginx', 'star_count': 7, 'pull_count': 9999}]}); await tester.pumpAndSettle();
    pending[0].complete({'results': [{'repo_name': 'nginx', 'star_count': 100}]}); await tester.pumpAndSettle();
    expect(registry._results.single.stars, 7);
    fail = true; await registry._search(); await tester.pumpAndSettle();
    expect(registry._metadataFailed, isTrue); expect(registry._results.single.name, 'nginx'); expect(registry._busy, isFalse);
    final selecting = registry._selectTag(registry._results.single); await tester.pumpAndSettle();
    final tags = tester.state<_ContainerImageTagDialogState>(find.byType(_ContainerImageTagDialog));
    expect(tags._failed, isTrue);
    tags._tag.text = '-invalid'; tags.setState(() {}); await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '确定')).onPressed, isNull);
    tags._tag.text = 'v2-manual'; tags.setState(() {}); await tester.pumpAndSettle();
    await tester.tap(find.text('确定')); await tester.pumpAndSettle(); await selecting;
    expect(registry._tags['nginx'], 'v2-manual');
    fail = false; await registry._search(); await tester.pumpWidget(const SizedBox());
    pending.last.complete({'results': [{'repo_name': 'nginx', 'star_count': 8}]}); await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('镜像与数据卷延迟加载、筛选、创建后刷新且六语言宽窄屏可用', (tester) async {
    for (final locale in AppLocalizations.supportedLocales) {
      final l=await AppLocalizations.delegate.load(locale);
      for (final width in [1180.0,420.0]) {
        final calls=<String>[];
        var created=false;
        Future<String> run(String command) async {
          calls.add(command);
          if(command.contains("'context' 'show'"))return 'desktop-linux';
          if(command.contains("'ps'"))return '';
          if(command.contains("'search'"))return '{"Name":"nginx","Description":"Web server","StarCount":10,"IsOfficial":true}';
          if(command.contains("'image' 'ls'"))return '{"Repository":"nginx","Tag":"alpine","ID":"sha256:123456789abcdef","Size":"20MB","CreatedAt":"2026-10-01T08:00:00Z","Containers":"0"}';
          if(command.contains("'volume' 'ls'"))return jsonEncode({'Name':created?'new-data':'data','Driver':'local'});
          if(command.contains("'volume' 'inspect'"))return jsonEncode([{'Name':created?'new-data':'data','Driver':'local','CreatedAt':'2026-10-01T08:00:00Z'}]);
        if(command.contains("'system' 'df'"))return command.contains('.Images')?jsonEncode([{'ID':'sha256:123456789abcdef','Containers':'0'}]):jsonEncode([{'Name':created?'new-data':'data','Size':'128MB','Links':'1'}]);
          return '{}';
        }
        Future<String> operate(String command,{required Duration timeout,void Function(String)? onOutput,bool Function()? isCancelled}) async {
          expect(command,contains("'--context' 'desktop-linux'"));if(command.contains("'pull'")){onOutput?.call('下载中');return 'nginx:latest';}
          expect(command,contains("'volume' 'create' 'new-data'"));
          created=true;onOutput?.call('new-data');return 'new-data';
        }
        await tester.binding.setSurfaceSize(Size(width,1000));
        final theme=width<500?OpenHandTheme.dark(OpenHandThemePreset.tundraGreen):OpenHandTheme.light(OpenHandThemePreset.tundraGreen);
        await tester.pumpWidget(_SettingsApp(locale:locale,localizationsDelegates:AppLocalizations.localizationsDelegates,supportedLocales:AppLocalizations.supportedLocales,
          theme:theme.copyWith(textTheme:theme.textTheme.apply(fontFamily:Platform.environment['MAINTENANCE_FONT']==null?null:'运维预览字体')),
          builder:(context,child)=>MediaQuery(data:MediaQuery.of(context).copyWith(textScaler:TextScaler.linear(width<500?1.5:1)),child:child!),
          home:Scaffold(body:RepaintBoundary(key:const ValueKey('资源预览'),child:_MachineContainerPanel(sessionId:'会话',terminalId:'终端',run:run,operate:operate,windows:false,shell:MachineTerminalCommandShell.posix)))));
        await tester.pumpAndSettle();
        expect(calls.any((c)=>c.contains("'image' 'ls'")),isFalse);
        await tester.tap(find.widgetWithText(ChoiceChip,l.maintenanceImages));await tester.pumpAndSettle();
        var state=tester.state<_MachineContainerResourcesState>(find.byType(_MachineContainerResources));
        expect(state._resources.single.name,'nginx');expect(state._error,isEmpty);
        state._search.text='absent';state.setState((){});await tester.pumpAndSettle();expect(find.text('nginx'),findsNothing);
        state._search.clear();state.setState((){});await tester.pumpAndSettle();
        final searching=state._open(search:true);await tester.pumpAndSettle();
        final registry=tester.state<_ContainerRegistryDialogState>(find.byType(_ContainerRegistryDialog));
        registry._query.text='nginx';await registry._search();await tester.pumpAndSettle();expect(registry._results.single.name,'nginx');
        final pulling=registry._openImage('nginx');await tester.pumpAndSettle();
        final download=tester.state<_ContainerResourceFormDialogState>(find.byType(_ContainerResourceFormDialog));
        await download._submit();await tester.pumpAndSettle();expect(download._completed,isTrue);
        await tester.ensureVisible(find.text(l.maintenanceResourceCloseRefresh));await tester.tap(find.text(l.maintenanceResourceCloseRefresh));await tester.pumpAndSettle();await pulling;
        await tester.tap(find.descendant(of:find.byType(_ContainerRegistryDialog),matching:find.byTooltip(openHandCloseLabel(tester.element(find.byType(_ContainerRegistryDialog))))));
        await tester.pumpAndSettle();await searching;

        await tester.tap(find.widgetWithText(ChoiceChip,l.maintenanceVolumes));await tester.pumpAndSettle();
        state=tester.state<_MachineContainerResourcesState>(find.byType(_MachineContainerResources));
        expect(state._resources.single.size,'128MB');expect(state._resources.single.references,1);
        expect(find.text('2026-10-01 08:00:00'),findsOneWidget);expect(state._error,isEmpty);
        if(Platform.environment['MAINTENANCE_PREVIEW']!=null && locale==const Locale('zh')) {
          await tester.runAsync(()async{final boundary=tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('资源预览')));
            final image=await boundary.toImage(pixelRatio:1.5);final bytes=await image.toByteData(format:ui.ImageByteFormat.png);
            await File('/tmp/container-volumes-${width.toInt()}.png').writeAsBytes(bytes!.buffer.asUint8List());image.dispose();});
        }
        await tester.ensureVisible(find.text(l.maintenanceVolumeCreate));await tester.tap(find.text(l.maintenanceVolumeCreate));await tester.pumpAndSettle();
        final form=tester.state<_ContainerResourceFormDialogState>(find.byType(_ContainerResourceFormDialog));
        form._controller('name').text='new-data';await form._submit();await tester.pumpAndSettle();
        expect(form._completed,isTrue);expect(find.text(l.maintenanceResourceSuccess),findsOneWidget);
        await tester.ensureVisible(find.text(l.maintenanceResourceCloseRefresh));await tester.tap(find.text(l.maintenanceResourceCloseRefresh));await tester.pumpAndSettle();
        expect(state._resources.single.name,'new-data');expect(tester.takeException(),isNull);
        await tester.pumpWidget(const SizedBox());
      }
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('创建容器表单六语言适配结构化配置且不提前执行', (tester) async {
    for(final locale in AppLocalizations.supportedLocales){
      final l=await AppLocalizations.delegate.load(locale);
      for(final width in [1180.0,420.0]){
        final calls=<String>[];
        final client=MachineContainerClient(runtime:MachineContainerRuntime.docker,run:(command)async{calls.add(command);return 'created-container';});
        await tester.binding.setSurfaceSize(Size(width,1000));
        final theme=width<500?OpenHandTheme.dark(OpenHandThemePreset.tundraGreen):OpenHandTheme.light(OpenHandThemePreset.tundraGreen);
        await tester.pumpWidget(_SettingsApp(locale:locale,localizationsDelegates:AppLocalizations.localizationsDelegates,supportedLocales:AppLocalizations.supportedLocales,
          theme:theme.copyWith(platform:width<500?TargetPlatform.iOS:TargetPlatform.macOS,textTheme:theme.textTheme.apply(fontFamily:Platform.environment['MAINTENANCE_FONT']==null?null:'运维预览字体')),
          builder:(context,child)=>MediaQuery(data:MediaQuery.of(context).copyWith(textScaler:TextScaler.linear(width<500?1.5:1)),child:child!),
          home:Scaffold(body:RepaintBoundary(key:const ValueKey('创建预览'),child:_ContainerResourceFormDialog(client:client,action:_ContainerResourceAction.createContainer,timeout:const Duration(seconds:60))))));
        await tester.pumpAndSettle();
        final form=tester.state<_ContainerResourceFormDialogState>(find.byType(_ContainerResourceFormDialog));
        expect(calls,isEmpty);form._controller('image').text='nginx:alpine';form._controller('name').text='web';
        form.setState((){form._ports.add({'address':'127.0.0.1','host':'8080','container':'80'});form._environment.add({'key':'MODE','value':'production'});form._mounts.add({'source':'data','target':'/data','readonly':'true'});});
        await tester.pumpAndSettle();
        for (final title in [maintenanceLabel(form.context,'端口'),maintenanceLabel(form.context,'环境变量'),l.maintenanceContainerMounts]) {
          final section=find.byWidgetPredicate((widget)=>widget is _MaintenanceSection && widget.title==title);
          final header=find.descendant(of:section,matching:find.byType(ListTile)).first;
          await tester.ensureVisible(header);await tester.tap(header);await tester.pumpAndSettle();expect(tester.takeException(),isNull);
        }
        await tester.ensureVisible(find.text(l.maintenanceResourceAdvanced));await tester.tap(find.text(l.maintenanceResourceAdvanced));await tester.pumpAndSettle();
        expect(find.text(l.maintenanceDetailRestartPolicy),findsOneWidget);expect(tester.takeException(),isNull);
        expect(find.byType(CupertinoSwitch), findsNothing);
        for (final title in [l.maintenanceContainerStartAfterCreate, l.maintenanceReadOnlyMount]) {
          final tile = find.widgetWithText(SwitchListTile, title);
          final toggle = find.descendant(of: tile, matching: find.byType(Switch));
          await tester.ensureVisible(toggle); await tester.pumpAndSettle();
          expect(tester.widget<Switch>(toggle).value, isTrue);
          await tester.tap(toggle); await tester.pumpAndSettle();
          expect(tester.widget<Switch>(toggle).value, isFalse);
          await tester.tap(toggle); await tester.pumpAndSettle();
          expect(tester.widget<Switch>(toggle).value, isTrue);
          expect(tester.takeException(), isNull);
        }

        if(Platform.environment['MAINTENANCE_PREVIEW']!=null && locale==const Locale('zh')){
          await tester.ensureVisible(find.byWidgetPredicate((widget)=>widget is TextField && widget.controller==form._controller('image')));await tester.pumpAndSettle();
          await tester.runAsync(()async{final boundary=tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('创建预览')));
            final image=await boundary.toImage(pixelRatio:1.5);final bytes=await image.toByteData(format:ui.ImageByteFormat.png);
            await File('/tmp/container-create-${width.toInt()}.png').writeAsBytes(bytes!.buffer.asUint8List());image.dispose();});
        }
        await form._submit();await tester.pumpAndSettle();
        expect(calls.single,contains("'--publish' '127.0.0.1:8080:80/tcp'"));expect(calls.single,contains("'--env' 'MODE=production'"));
        expect(calls.single,contains("'--mount' 'type=volume,source=data,target=/data,readonly'"));expect(form._completed,isTrue);
        await form._submit();expect(calls.length,1);
        await tester.pumpWidget(const SizedBox());
      }
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('下载输出有界、取消和超时后需刷新确认且重复点击不重复提交', (tester) async {
    final pending=Completer<String>();var calls=0;bool Function()? cancelled;
    final client=MachineContainerClient(runtime:MachineContainerRuntime.docker,run:(_)async=>throw StateError('不应使用默认采集通道'));
    Future<String> operate(String command,{required Duration timeout,void Function(String)? onOutput,bool Function()? isCancelled})async{
      calls++;cancelled=isCancelled;expect(timeout,const Duration(minutes:15));onOutput?.call('a'*40000);return pending.future;
    }
    await tester.binding.setSurfaceSize(const Size(1000,900));
    await tester.pumpWidget(_SettingsApp(locale:const Locale('zh'),localizationsDelegates:AppLocalizations.localizationsDelegates,supportedLocales:AppLocalizations.supportedLocales,
      home:Scaffold(body:_ContainerResourceFormDialog(client:client,action:_ContainerResourceAction.pull,image:'nginx:alpine',timeout:const Duration(minutes:15),operate:operate))));
    await tester.pumpAndSettle();final form=tester.state<_ContainerResourceFormDialogState>(find.byType(_ContainerResourceFormDialog));
    final work=form._submit();await tester.pump();await tester.pump(const Duration(milliseconds:110));await form._submit();
    expect(calls,1);expect(form._output.length,machineContainerOperationOutputLimit);
    form.setState(()=>form._cancelled=true);expect(cancelled!(),isTrue);
    pending.completeError(TimeoutException('模拟下载超时'));await work;await tester.pumpAndSettle();
    expect(form._uncertain,isTrue);expect(form._busy,isFalse);await form._submit();expect(calls,1);expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox());await tester.binding.setSurfaceSize(null);
  });
}

void containerInteractionChecks() {
  testWidgets('后台采集不锁定容器菜单，用户读取优先且取消结果不写回', (tester) async {
    final calls=<String>[];
    Completer<String>? pending;
    bool Function()? cancelled;
    var active=0, peak=0;
    Future<String> query(String command,{required Duration timeout,void Function(String)? onOutput,bool Function()? isCancelled}) async {
      calls.add(command);active++;peak=math.max(peak,active);
      try {
        if(command.contains("'context' 'show'"))return 'default';
        if(command.contains("'ps'"))return '{"ID":"abc123","Names":"worker","State":"running","Image":"nginx"}';
        if(command.contains("'info'")) {
          if(pending!=null){cancelled=isCancelled;return await pending!.future;}
          return '{"ServerVersion":"原有版本"}';
        }
        if(command.contains('.State.StartedAt'))return '"abc123"\t"2026-10-01T08:00:00Z"\t{}';
        if(command.contains("'logs'"))return '应用日志';
        if(command.contains("'inspect'"))return '{"Name":"worker"}';
        return '{}';
      } finally {active--;}
    }
    Future<String> run(String command)=>query(command,timeout:const Duration(seconds:30));
    await tester.binding.setSurfaceSize(const Size(1300,1000));
    await tester.pumpWidget(_SettingsApp(locale:const Locale('zh'),localizationsDelegates:AppLocalizations.localizationsDelegates,
      supportedLocales:AppLocalizations.supportedLocales,home:Scaffold(body:_MachineContainerPanel(
        sessionId:'会话',terminalId:'终端',run:run,query:query,windows:false,shell:MachineTerminalCommandShell.posix))));
    await selectContainerList(tester);
    await tester.pumpAndSettle();
    final panel=tester.state<_MachineContainerPanelState>(find.byType(_MachineContainerPanel));
    final metadata=panel._metadata;
    pending=Completer<String>();
    final refreshing=panel.refresh();await tester.pump();
    expect(panel._busy,isTrue);expect(cancelled,isNotNull);
    final menu=tester.widget<OpenHandOperationalRowMenu>(find.byType(OpenHandOperationalRowMenu));
    expect(menu.onDetails,isNotNull);expect(menu.actions,isNotEmpty);
    final statsBefore=calls.where((command)=>command.contains("'stats'")).length;
    final opening=panel._open(panel._entries.single,'详情');await tester.pump();
    expect(cancelled!(),isTrue);expect(panel._busy,isFalse);
    expect(find.byType(_ContainerReportDialog),findsOneWidget);
    expect(calls.where((command)=>command.contains("'inspect' 'abc123'")),isEmpty);
    pending!.complete('{"ServerVersion":"不应显示的旧结果"}');pending=null;
    await refreshing;await tester.pumpAndSettle();
    expect(panel._metadata,metadata);expect(panel._collectionIssues,isEmpty);
    expect(calls.where((command)=>command.contains("'stats'")).length,statsBefore);
    expect(peak,1);
    final count=calls.length;
    await tester.tap(find.byTooltip('关闭'));await tester.pumpAndSettle();await opening;
    expect(calls.length,count);expect(panel._overlay,isFalse);
    final logs=panel._open(panel._entries.single,'日志');await tester.pumpAndSettle();
    expect(tester.state<_ContainerReportDialogState>(find.byType(_ContainerReportDialog))._text,'应用日志');
    await tester.tap(find.byTooltip('关闭'));await tester.pumpAndSettle();await logs;
    expect(panel._busy,isFalse);expect(panel._overlay,isFalse);expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox());await tester.binding.setSurfaceSize(null);
  });

  testWidgets('关闭仍在加载的详情可立即打开日志，旧请求释放终端后才发送新命令', (tester) async {
    final pending=Completer<String>();bool Function()? stopped;var logs=0;
    Future<String> query(String command,{required Duration timeout,void Function(String)? onOutput,bool Function()? isCancelled})async {
      if(command.contains("'context' 'show'"))return 'default';
      if(command.contains("'ps'"))return '{"ID":"abc123","Names":"worker","State":"running"}';
      if(command.contains('.State.StartedAt'))return '';
      if(command.contains("'inspect' 'abc123'")){stopped=isCancelled;return pending.future;}
      if(command.contains("'logs'")){logs++;return '新日志';}
      return '{}';
    }
    await tester.binding.setSurfaceSize(const Size(1100,900));
    await tester.pumpWidget(_SettingsApp(locale:const Locale('zh'),localizationsDelegates:AppLocalizations.localizationsDelegates,
      supportedLocales:AppLocalizations.supportedLocales,home:Scaffold(body:_MachineContainerPanel(
        sessionId:'会话',terminalId:'终端',run:(command)=>query(command,timeout:const Duration(seconds:30)),query:query,windows:false,shell:MachineTerminalCommandShell.posix))));
    await selectContainerList(tester);
    await tester.pumpAndSettle();final panel=tester.state<_MachineContainerPanelState>(find.byType(_MachineContainerPanel));
    final first=panel._open(panel._entries.single,'详情');await tester.pump();await tester.pump(const Duration(seconds:1));
    expect(stopped,isNotNull);
    tester.widget<_MachineTerminalDialogHeader>(find.descendant(of:find.byType(_ContainerReportDialog),matching:find.byType(_MachineTerminalDialogHeader))).onClose();await tester.pump();await tester.pump(const Duration(seconds:1));await first;
    expect(stopped!(),isTrue);expect(panel._overlay,isFalse);
    final second=panel._open(panel._entries.single,'日志');await tester.pump();await tester.pump(const Duration(seconds:1));
    expect(find.byType(_ContainerReportDialog),findsOneWidget);expect(logs,0);
    pending.completeError(StateError('模拟已取消的详情请求'));await tester.pumpAndSettle();
    final report=tester.state<_ContainerReportDialogState>(find.byType(_ContainerReportDialog));
    expect(report._text,'新日志');expect(report._error,isEmpty);expect(logs,1);
    await tester.tap(find.byTooltip('关闭'));await tester.pumpAndSettle();await second;
    expect(panel._error,isEmpty);expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox());await tester.binding.setSurfaceSize(null);
  });

  testWidgets('刷新中切换运行时取消旧请求，旧结果和结束回调不覆盖新目标', (tester) async {
    Completer<String>? oldInfo, newInfo;
    bool Function()? oldCancelled;
    Future<String> query(String command,{required Duration timeout,void Function(String)? onOutput,bool Function()? isCancelled}) async {
      final podman=command.startsWith("'podman'");
      if(command.contains("'context' 'show'"))return 'default';
      if(command.contains("'ps'"))return jsonEncode({'ID':podman?'new123':'old123','Names':podman?'新容器':'旧容器','State':'running'});
      if(command.contains("'info'")) {
        if(podman)return newInfo!.future;
        if(oldInfo!=null){oldCancelled=isCancelled;return oldInfo!.future;}
      }
      if(command.contains('.State.StartedAt'))return '';
      return '{}';
    }
    await tester.binding.setSurfaceSize(const Size(1200,1000));
    await tester.pumpWidget(_SettingsApp(locale:const Locale('zh'),localizationsDelegates:AppLocalizations.localizationsDelegates,
      supportedLocales:AppLocalizations.supportedLocales,home:Scaffold(body:_MachineContainerPanel(
        sessionId:'会话',terminalId:'终端',run:(command)=>query(command,timeout:const Duration(seconds:30)),query:query,windows:false,shell:MachineTerminalCommandShell.posix))));
    await selectContainerList(tester);
    await tester.pumpAndSettle();final panel=tester.state<_MachineContainerPanelState>(find.byType(_MachineContainerPanel));
    oldInfo=Completer<String>();newInfo=Completer<String>();
    final refresh=panel.refresh();await tester.pump();
    final runtime=tester.widget<_MaintenanceToolbarMenu<String>>(find.byType(_MaintenanceToolbarMenu<String>));
    expect(runtime.enabled,isTrue);runtime.onSelected('podman');await tester.pump();
    expect(oldCancelled!(),isTrue);expect(panel._entries,isEmpty);
    oldInfo!.completeError(StateError('旧目标已断开'));await refresh;await tester.pump();
    expect(panel._runtime,MachineContainerRuntime.podman);expect(panel._entries.single.name,'新容器');
    expect(panel._busy,isTrue);expect(panel._error,isEmpty);expect(panel._collectionIssues,isEmpty);
    newInfo!.complete('{"Host":{"Hostname":"新目标"}}');await tester.pumpAndSettle();
    expect(panel._busy,isFalse);expect(panel._metadata,contains('新目标'));expect(panel._entries.single.id,'new123');
    expect(tester.takeException(),isNull);await tester.pumpWidget(const SizedBox());await tester.binding.setSurfaceSize(null);
  });

  testWidgets('镜像容量刷新期间菜单和子导航可用，只读详情与仓库搜索关闭不刷新列表', (tester) async {
    final calls=<String>[];Completer<String>? usage;bool Function()? cancelled;
    Future<String> query(String command,{required Duration timeout,void Function(String)? onOutput,bool Function()? isCancelled})async {
      calls.add(command);
      if(command.contains("'context' 'show'"))return 'default';
      if(command.contains("'ps'"))return '';
      if(command.contains("'image' 'ls'"))return '{"Repository":"nginx","Tag":"latest","ID":"sha256:123","Size":"20MB"}';
      if(command.contains("'system' 'df'")) {if(usage!=null){cancelled=isCancelled;return usage!.future;}return '[{"ID":"sha256:123","Containers":"1"}]';}
      if(command.contains("'image' 'inspect'"))return '[{"Id":"sha256:123","RepoTags":["nginx:latest"]}]';
      if(command.contains("'image' 'history'"))return '';
      return '{}';
    }
    await tester.binding.setSurfaceSize(const Size(1200,1000));
    await tester.pumpWidget(_SettingsApp(locale:const Locale('zh'),localizationsDelegates:AppLocalizations.localizationsDelegates,
      supportedLocales:AppLocalizations.supportedLocales,home:Scaffold(body:_MachineContainerPanel(
        sessionId:'会话',terminalId:'终端',run:(command)=>query(command,timeout:const Duration(seconds:30)),query:query,windows:false,shell:MachineTerminalCommandShell.posix))));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip,'镜像'));await tester.pumpAndSettle();
    final panel=tester.state<_MachineContainerPanelState>(find.byType(_MachineContainerPanel));
    final resources=tester.state<_MachineContainerResourcesState>(find.byType(_MachineContainerResources));
    usage=Completer<String>();final refresh=panel.refresh(applyScope:true);await tester.pump();
    expect(resources._busy,isTrue);expect(panel._overlay,isFalse);
    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip,'数据卷')).onSelected,isNotNull);
    expect(tester.widget<OpenHandOperationalRowMenu>(find.byType(OpenHandOperationalRowMenu)).onDetails,isNotNull);
    final details=resources._open(resource:resources._resources.single);await tester.pump();expect(cancelled!(),isTrue);
    usage!.complete('[{"ID":"sha256:123","Containers":"99"}]');usage=null;await refresh;await tester.pumpAndSettle();
    expect(resources._resources.single.references,isNull);
    final before=calls.where((command)=>command.contains("'image' 'ls'")).length;
    await tester.tap(find.byTooltip('关闭'));await tester.pumpAndSettle();await details;
    expect(calls.where((command)=>command.contains("'image' 'ls'")).length,before);
    final search=resources._open(search:true);await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('关闭'));await tester.pumpAndSettle();await search;
    expect(calls.where((command)=>command.contains("'image' 'ls'")).length,before);
    expect(resources._overlay,isFalse);expect(panel._overlay,isFalse);expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox());await tester.binding.setSurfaceSize(null);
  });
}

''';

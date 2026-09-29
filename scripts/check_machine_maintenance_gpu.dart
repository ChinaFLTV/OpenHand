import 'dart:convert';
import 'dart:io';

import 'package:openhand/features/machine_terminal/machine_maintenance_gpu.dart';
import 'package:openhand/features/machine_terminal/machine_maintenance_parallel.dart';
import 'package:openhand/features/machine_terminal/machine_maintenance_platform.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void main() {
  final parallel = parallelMaintenanceCommand(
    'section platform\nLinux\n$machineGpuLinuxCollection\nsection end\n',
    8,
    4,
  );
  check(
    parallel.contains('gpu_probe()') &&
        RegExp('common\\.sh').allMatches(parallel).length > 10,
    'GPU 子进程缺少采集超时函数',
  );
  final fields = List.generate(1200, (i) => '<metric$i>$i</metric$i>').join();
  final full =
      '<nvidia_smi_log><gpu><uuid>GPU-LARGE</uuid><ecc_errors>$fields</ecc_errors></gpu></nvidia_smi_log>';
  final expanded = MachineGpuReport.parse({'gpu_details': full});
  check(expanded.single.rows.length == 1201, '大卡详情仍被 700 字段限制截断');
  final partial = MachineGpuReport.parse({
    'gpu_details': full.replaceFirst(
      '</nvidia_smi_log>',
      '<gpu><uuid>GPU-BROKEN',
    ),
  });
  check(
    partial.single.rows.length == 1201 && partial.single.issue == 'truncated',
    '尾部截断丢弃了已完整采集的 GPU',
  );
  final many = MachineGpuReport.parse({
    'gpu_details':
        '<nvidia_smi_log>${List.generate(8, (i) => '<gpu><uuid>GPU-$i</uuid><ecc_errors>$fields</ecc_errors></gpu>').join()}</nvidia_smi_log>',
  });
  check(
    many.length == 8 && many.every((r) => r.rows.length == 1201),
    '多卡指标不完整',
  );
  final fallback = MachineGpuSnapshot.parse({
    'gpu_nvidia': '字段不支持',
    'gpu_details':
        '<nvidia_smi_log><gpu><uuid>GPU-FALLBACK</uuid><product_name>H100</product_name><fb_memory_usage><used>1024 MiB</used><total>81920 MiB</total></fb_memory_usage><utilization><gpu_util>0 %</gpu_util></utilization></gpu></nvidia_smi_log>',
  });
  check(
    fallback.devices.single.metrics['memoryUsed'] == 1073741824 &&
        fallback.devices.single.metrics['util'] == 0,
    'CSV 失败时 XML 未恢复设备及指标',
  );
  final dcgm = MachineGpuReport.parse({
    'gpu_dcgm_metrics': '# Entity SMCLK MEMCLK\nGPU 0 N/A 1000',
    'gpu_dcgm_health': 'Unable to connect\n__GPU_PROBE_EXIT_1__',
    'gpu_topology': 'GPU0 GPU1 CPU Affinity\nGPU0 X NV4 0-31',
  });
  check(dcgm.length == 3 && dcgm.last.raw.contains('N/A'), 'DCGM 原始单位或不可用状态丢失');
  check(
    dcgm.firstWhere((r) => r.title.contains('健康')).issue.isNotEmpty,
    'DCGM 连接失败未提示',
  );
  final windowsScript = MachineMaintenancePlatformAdapter.forPlatform(
    'Windows',
  ).collect(4, workers: 8);
  check(
    windowsScript.contains('4000000') && windowsScript.contains('gpuCommand'),
    'Windows 大输出仍使用小管道限制',
  );
  final reports = MachineGpuReport.parse({
    'gpu_details':
        '<nvidia_smi_log><driver_version>580</driver_version><cuda_version>13.0</cuda_version><attached_gpus>1</attached_gpus><gpu id="0000:01:00.0"><uuid>GPU-A</uuid><gpu_fabric_info><state>Completed</state><status>Success</status></gpu_fabric_info><ecc_errors><volatile><single_bit><total>0</total></single_bit></volatile></ecc_errors><processes><process_info><pid>42</pid><type>C</type><used_memory>100 MiB</used_memory></process_info><process_info><pid>43</pid><type>G</type></process_info></processes></gpu></nvidia_smi_log>',
    'gpu_toolkit':
        '{"cuda":{"version":"12.8.0"},"cuda_cublas":{"version":"12.8.3"}}',
    'gpu_stack':
        'CUDA Toolkit\tversion\trelease 12.8\nlibcudnn9\tversion\t9.8.0\n错误输出',
    'gpu_fabric':
        'LoadState=loaded\nActiveState=active\nMainPID=123\nMemoryCurrent=65536\n',
    'gpu_links':
        'GPU 0: H100 (UUID: GPU-A)\n Link 0: 26.562 GB/s\n Link 1: <inactive>',
    'gpu_link_errors':
        'GPU 0: H100\n Link 0:\n  CRC Flit Error: 0\n  Replay Error: 2',
  });
  check(
    reports.first.rows.any((r) => r[0] == 'cuda_version' && r[1] == '13.0'),
    '驱动兼容版本未保留',
  );
  check(
    reports.firstWhere((r) => r.title == 'CUDA Toolkit').rows.single[1] ==
        'release 12.8',
    '工具包版本与驱动兼容版本混淆',
  );
  check(
    reports.any(
      (r) =>
          r.title == 'cuda_cublas (version.json)' &&
          r.rows.single[1] == '12.8.3',
    ),
    'CUDA 组件清单未解析',
  );
  final details = reports.firstWhere((r) => r.title == 'GPU-A');
  check(
    details.rows.any(
      (r) => r[0] == 'processes/process_info[2]/pid' && r[1] == '43',
    ),
    '图形进程或重复节点丢失',
  );
  check(
    details.rows.any((r) => r[0].startsWith('ecc_errors/') && r[1] == '0'),
    '零错误计数丢失',
  );
  check(
    reports.firstWhere((r) => r.title == 'NVLink').rows.length == 2,
    '链路状态解析失败',
  );
  check(reports.last.rows.last[1] == '2', '链路错误计数解析失败');
  check(
    MachineGpuReport.parse({'gpu_details': '<nvidia_smi_log>'}).single.issue ==
        'format',
    '截断 XML 未标识',
  );
  check(
    MachineGpuReport.parse({
          'gpu_details': 'Insufficient Permissions',
        }).single.issue ==
        'permission',
    '权限错误未分类',
  );
  check(
    MachineGpuReport.parse({'gpu_details': 'not supported'}).single.issue ==
        'unsupported',
    '不支持未分类',
  );
  check(
    MachineGpuReport.parse({
      'gpu_details': '<unexpected/>',
    }).single.rows.isEmpty,
    '无关 XML 被识别为 GPU 数据',
  );

  final nvidia = MachineGpuSnapshot.parse({
    'gpu_nvidia':
        'GPU-1,"NVIDIA, Test",550.1,00000000:01:00.0,45,1024,8192,60,80.5,150,1800,7000,0,P2\nGPU-2,Second,550.1,00000000:02:00.0,N/A,N/A,8192,N/A,N/A,N/A,N/A,N/A,N/A,P8',
    'gpu_processes': 'GPU-1,42,"worker, compute",128\n错误信息',
    'gpu_drm': 'id=card0\nbus=0000:01:00.0\nvendor=0x10de\n',
  });
  check(nvidia.devices.length == 2, 'PCI 设备去重失败');
  check(nvidia.devices.first.name == 'NVIDIA, Test', '带逗号设备名解析失败');
  check(nvidia.devices.first.metrics['memoryUsed'] == 1073741824, '显存单位换算失败');
  check(nvidia.devices.first.metrics['fan'] == 0, '零值被错误丢弃');
  check(!nvidia.devices.last.metrics.containsKey('util'), '不可用利用率被伪造');
  check(nvidia.processes.single[2] == 'worker, compute', '计算进程解析失败');
  final amd = MachineGpuSnapshot.parse({
    'gpu_drm':
        'id=card0\nbus=0000:03:00.0\nvendor=0x1002\ndevice=0x1234\ndriver=amdgpu\ngpu_busy_percent=150\nmem_info_vram_used=4096\nmem_info_vram_total=8192\ntemp1_input=45000\npower1_average=30000000\nfan1_input=1000\n',
  }).devices.single;
  check(
    amd.metrics['temperature'] == 45 && amd.metrics['power'] == 30,
    'AMD 传感器单位错误',
  );
  check(!amd.metrics.containsKey('util'), '越界利用率未拒绝');
  final apple = MachineGpuSnapshot.parse({
    'gpu_apple': jsonEncode({
      'SPDisplaysDataType': [
        {
          'sppci_model': 'Apple M4',
          'sppci_cores': '10',
          'spdisplays_ndrvs': [
            {'_name': 'Display', '_spdisplays_pixels': '3024 x 1964'},
          ],
        },
      ],
    }),
    'gpu_accelerators':
        '+-o AGX\n"model" = "Apple M4"\n"PerformanceStatistics" = {"Device Utilization %"=22,"In use system memory"=123456,"Renderer Utilization %"=20}',
  });
  check(apple.devices.single.metrics['util'] == 22, 'Apple 利用率解析失败');
  check(
    apple.devices.single.metrics['sharedUsed'] == 123456 &&
        !apple.devices.single.metrics.containsKey('memoryUsed'),
    '共享内存不应标成显存',
  );
  check(apple.displays.single[2] == '3024 x 1964', '显示器解析失败');
  check(
    MachineGpuSnapshot.parse({'gpu_apple': '{"broken"'}).devices.isEmpty,
    '截断 JSON 被当成有效设备',
  );
  check(
    MachineGpuSnapshot.parse({
      'gpu_nvidia': '驱动不可用',
      'gpu_processes': '',
    }).devices.isEmpty,
    '错误输出被当成设备',
  );
  check(
    MachineGpuSnapshot.number('NaN') == null &&
        MachineGpuSnapshot.number('-1') == null,
    '非法数值未拒绝',
  );
  final windows = MachineGpuSnapshot.parse({
    'gpu_windows':
        'VideoController1\tIntel Graphics\tIntel\t1.2\tOK\tPCI\\VEN_8086',
  });
  check(windows.devices.single.metrics.isEmpty, 'WMI 不应推测显存和负载');
  stdout.writeln('GPU 多平台解析、单位换算、去重、共享内存与异常边界检查通过。');
}

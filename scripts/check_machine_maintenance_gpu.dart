import 'dart:convert';
import 'dart:io';

import 'package:openhand/features/machine_terminal/machine_maintenance_gpu.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void main() {
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

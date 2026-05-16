// 解析 launcher 抛出的错误文案 → 结构化诊断的回归测试。

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/web_reverse/web_reverse_launch_diagnosis.dart';

void main() {
  test('Profile 锁子串命中 → "Profile 锁被另一个 Chrome 实例占用"', () {
    final d = WebReverseLaunchDiagnosis.parse(
      'CDP 握手超时\n浏览器 stderr 摘要：\nProfile is in use, locked by '
      'another instance.\nSingletonLock present.',
    );
    expect(d.causes.first.title, contains('Profile 锁'));
    expect(d.fullText, contains('Profile is in use'));
    expect(d.phenomenon, 'CDP 握手超时');
  });

  test('端口占用子串命中 → "远端调试端口被占用"', () {
    final d = WebReverseLaunchDiagnosis.parse(
      '浏览器进程启动失败\n[ERROR] address already in use: 9222',
    );
    expect(
      d.causes.any((c) => c.title.contains('远端调试端口')),
      isTrue,
    );
  });

  test('沙箱失败子串命中 → "沙箱初始化失败"', () {
    final d = WebReverseLaunchDiagnosis.parse(
      '握手超时\nNo usable sandbox! Update your kernel or see ...',
    );
    expect(
      d.causes.any((c) => c.title.contains('沙箱')),
      isTrue,
    );
  });

  test('未匹配任何规则 → 给一条兜底建议', () {
    final d = WebReverseLaunchDiagnosis.parse('完全无关的报错');
    expect(d.causes, isNotEmpty);
    expect(d.causes.first.suggestion, isNotEmpty);
  });

  test('多条规则同时命中 → 全部出现', () {
    final d = WebReverseLaunchDiagnosis.parse(
      'CDP 握手超时\nProfile is in use\nAlso address already in use',
    );
    final titles = d.causes.map((c) => c.title).toList();
    expect(titles.any((t) => t.contains('Profile 锁')), isTrue);
    expect(titles.any((t) => t.contains('远端调试端口')), isTrue);
  });
}

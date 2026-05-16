// Profile 锁清理器：用临时目录模拟 Chrome 残留锁文件 → 调用清理 → 校验删除。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/web_reverse/web_reverse_profile_cleaner.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('oh_profile_clean_');
  });

  tearDown(() async {
    if (await tmp.exists()) {
      await tmp.delete(recursive: true);
    }
  });

  test('hasWebReverseProfileLocks: 空目录返回 false', () async {
    expect(await hasWebReverseProfileLocks(tmp.path), isFalse);
  });

  test('hasWebReverseProfileLocks: 根目录 SingletonLock 命中', () async {
    await File('${tmp.path}/SingletonLock').writeAsString('lock');
    expect(await hasWebReverseProfileLocks(tmp.path), isTrue);
  });

  test('hasWebReverseProfileLocks: Default/lockfile 命中', () async {
    final defDir = Directory('${tmp.path}/Default');
    await defDir.create();
    await File('${defDir.path}/lockfile').writeAsString('x');
    expect(await hasWebReverseProfileLocks(tmp.path), isTrue);
  });

  test('cleanWebReverseProfileLocks: 删除根 + Default 锁，保留其他文件', () async {
    final defDir = Directory('${tmp.path}/Default');
    await defDir.create();
    final keep = File('${tmp.path}/Cookies');
    await keep.writeAsString('please keep me');
    await File('${tmp.path}/SingletonLock').writeAsString('a');
    await File('${tmp.path}/SingletonSocket').writeAsString('b');
    await File('${defDir.path}/lockfile').writeAsString('c');
    final r = await cleanWebReverseProfileLocks(tmp.path);
    expect(r.deleted, 3);
    expect(await keep.exists(), isTrue);
    expect(await File('${tmp.path}/SingletonLock').exists(), isFalse);
    expect(await File('${defDir.path}/lockfile').exists(), isFalse);
  });

  test('cleanWebReverseProfileLocks: 空目录返回 0 + 友好提示', () async {
    final r = await cleanWebReverseProfileLocks(tmp.path);
    expect(r.deleted, 0);
    expect(r.messages.first, contains('未发现残留锁文件'));
  });

  test('cleanWebReverseProfileLocks: 不存在的目录走错误分支不抛', () async {
    final r =
        await cleanWebReverseProfileLocks('${tmp.path}/non-existent-subdir');
    expect(r.deleted, 0);
    expect(r.messages.first, contains('目录不存在'));
  });
}

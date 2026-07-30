import 'dart:io';

import '../../app/support/silent_log.dart';
import '../../shared/util/bounded_delete.dart';
import '../../shared/util/bounded_file_io.dart';
import '../../shared/util/input_value_parsing.dart';

const List<String> _webReverseProfileLockNames = <String>[
  'SingletonLock',
  'SingletonSocket',
  'SingletonCookie',
  'lockfile',
  'parent.lock',
];
const BoundedDeletePolicy _webReverseProfileLockDeletePolicy =
    BoundedDeletePolicy(
      maxEntries: 1,
      maxDepth: 0,
      operationTimeout: Duration(seconds: 3),
      totalTimeout: Duration(seconds: 5),
    );

Iterable<String> _webReverseProfileLockPaths(Directory root) sync* {
  for (final name in _webReverseProfileLockNames) {
    yield '${root.path}/$name';
  }
  for (final name in _webReverseProfileLockNames) {
    yield '${root.path}/Default/$name';
  }
}

/// 清理 Chrome 系浏览器的 Profile 锁文件（关闭浏览器后用），
/// 让被卡住的 user-data-dir 重新可用。
///
/// 处理对象：根目录与 `Default/` 子目录下的
/// SingletonLock / SingletonSocket / SingletonCookie /
/// lockfile / parent.lock —— 它们都是 Chrome 在 user-data-dir
/// 被另一实例占用时留下的"占位锁"，一旦原进程已退出，残留锁
/// 直接删除即可让新进程恢复使用，而不会影响 Cookies、Login Data
/// 等真正的 profile 内容。
///
/// 返回 (deleted, messages)：deleted 为成功删除的锁文件数，
/// messages 为面向用户的执行细节（可写到 SnackBar / 日志）。
Future<({int deleted, List<String> messages})> cleanWebReverseProfileLocks(
  String userDataDir,
) async {
  final messages = <String>[];
  var deleted = 0;
  final normalizedUserDataDir = nullIfBlank(userDataDir);
  if (normalizedUserDataDir == null) {
    return (deleted: 0, messages: <String>['user-data-dir 为空，未执行清理']);
  }
  final root = Directory(normalizedUserDataDir);
  if (await probeFileSystemEntityType(root.path, followLinks: true) !=
      FileSystemEntityType.directory) {
    return (deleted: 0, messages: <String>['目录不存在：$normalizedUserDataDir']);
  }
  // 仅清理 Chrome 已知的锁文件，避免误删用户数据。
  // 顺序：根目录的 SingletonLock 最常见，先动；Default/ 下的 lockfile
  // 是 LevelDB 锁，必须 Chrome 完全退出后才安全。
  for (final path in _webReverseProfileLockPaths(root)) {
    try {
      final type = await probeFileSystemEntityType(path);
      if (type == FileSystemEntityType.notFound) continue;
      if (type != FileSystemEntityType.link &&
          type != FileSystemEntityType.file) {
        messages.add('跳过（不是锁文件或符号链接）：$path');
        continue;
      }
      await deletePathBounded(
        File(path).absolute.path,
        policy: _webReverseProfileLockDeletePolicy,
        allowedRoot: root.absolute.path,
      );
      deleted++;
      messages.add('删除：$path');
    } catch (error, stack) {
      silentLog('web_reverse_profile_cleaner', '删除配置文件 $path', error, stack);
      messages.add('跳过（删除失败）：$path — $error');
    }
  }
  if (deleted == 0) {
    messages.add('未发现残留锁文件，profile 已是干净状态');
  }
  return (deleted: deleted, messages: messages);
}

/// 检查 user-data-dir 当前是否存在 Chrome 锁。
/// 用于按钮的 enabled / 文案切换（无锁时按钮置灰提示"已干净"）。
Future<bool> hasWebReverseProfileLocks(String userDataDir) async {
  final normalizedUserDataDir = nullIfBlank(userDataDir);
  if (normalizedUserDataDir == null) return false;
  final root = Directory(normalizedUserDataDir);
  if (await probeFileSystemEntityType(root.path, followLinks: true) !=
      FileSystemEntityType.directory) {
    return false;
  }
  for (final path in _webReverseProfileLockPaths(root)) {
    final type = await probeFileSystemEntityType(path);
    if (type == FileSystemEntityType.file ||
        type == FileSystemEntityType.link) {
      return true;
    }
  }
  return false;
}

import 'dart:io';

import '../../app/support/silent_log.dart';
import '../../shared/util/input_value_parsing.dart';

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
  if (!await root.exists()) {
    return (deleted: 0, messages: <String>['目录不存在：$normalizedUserDataDir']);
  }
  // 仅清理 Chrome 已知的锁文件，避免误删用户数据。
  // 顺序：根目录的 SingletonLock 最常见，先动；Default/ 下的 lockfile
  // 是 LevelDB 锁，必须 Chrome 完全退出后才安全。
  const lockNames = <String>[
    'SingletonLock',
    'SingletonSocket',
    'SingletonCookie',
    'lockfile',
    'parent.lock',
  ];
  // 探测 Default 子目录是否还在；不存在时只清根目录即可。
  final candidates = <File>[
    for (final n in lockNames) File('${root.path}/$n'),
    for (final n in lockNames) File('${root.path}/Default/$n'),
  ];
  for (final f in candidates) {
    try {
      if (!await f.exists()) continue;
      // SingletonLock 在 macOS / Linux 是符号链接，stat 会跟着走；
      // 用 FileSystemEntity.typeSync(followLinks:false) 区分。
      final type = FileSystemEntity.typeSync(f.path, followLinks: false);
      if (type == FileSystemEntityType.link) {
        await Link(f.path).delete();
      } else {
        await f.delete();
      }
      deleted++;
      messages.add('删除：${f.path}');
    } catch (error, stack) {
      silentLog(
        'web_reverse_profile_cleaner',
        'delete ${f.path}',
        error,
        stack,
      );
      messages.add('跳过（删除失败）：${f.path} — $error');
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
  if (!await root.exists()) return false;
  for (final n in const <String>[
    'SingletonLock',
    'SingletonSocket',
    'SingletonCookie',
    'lockfile',
    'parent.lock',
  ]) {
    if (await File('${root.path}/$n').exists()) return true;
    if (await File('${root.path}/Default/$n').exists()) return true;
  }
  return false;
}

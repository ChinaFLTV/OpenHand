import 'package:flutter/foundation.dart';

/// 仅在调试模式记录可安全忽略的非关键异常。
///
/// 用它替代空 catch，保留开发期可观测性，同时避免在发布版本产生噪声。
/// 发布构建中该方法为空操作，编译器可通过 `kDebugMode` 移除方法体。
///
/// 示例：
/// ```
/// try {
///   await _store.save(updatedSession);
/// } catch (error, stack) {
///   silentLog('ai_session_controller', '持久化更新后的会话', error, stack);
/// }
/// ```
@pragma('vm:prefer-inline')
void silentLog(String tag, String action, Object error, [StackTrace? stack]) {
  if (!kDebugMode) {
    return;
  }
  final detail = stack == null ? '$error' : '$error\n$stack';
  debugPrint('[$tag] 已忽略异常：$action -> $detail');
}

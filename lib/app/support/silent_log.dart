import 'package:flutter/foundation.dart';

/// 仅在调试模式记录已由调用方处理的异常，发布版本不输出。
@pragma('vm:prefer-inline')
void silentLog(String tag, String action, Object error, [StackTrace? stack]) {
  if (!kDebugMode) {
    return;
  }
  final detail = stack == null ? '$error' : '$error\n$stack';
  debugPrint('[$tag] 已忽略异常：$action -> $detail');
}

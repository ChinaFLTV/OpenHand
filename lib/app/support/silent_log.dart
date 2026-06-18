import 'package:flutter/foundation.dart';

/// Debug-only logger for non-critical, intentionally swallowed errors.
///
/// Use this instead of silent empty catch blocks when you want observability
/// during development without leaking noise into release builds.  In release
/// builds the call is a no-op (and the constant
/// `kDebugMode` allows the compiler to tree-shake the body).
///
/// Example:
/// ```
/// try {
///   await _store.save(updatedSession);
/// } catch (error, stack) {
///   silentLog('ai_session_controller', 'persist updated session', error, stack);
/// }
/// ```
@pragma('vm:prefer-inline')
void silentLog(String tag, String where, Object error, [StackTrace? stack]) {
  if (!kDebugMode) {
    return;
  }
  if (stack != null) {
    debugPrint('[$tag] swallowed: $where -> $error\n$stack');
  } else {
    debugPrint('[$tag] swallowed: $where -> $error');
  }
}
